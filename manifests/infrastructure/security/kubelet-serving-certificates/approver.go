// serving CSR の初回発行・更新を、Git 管理のノード台帳に照合して承認する。
package main

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/asn1"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"slices"
	"strings"
	"sync"
	"time"
)

const csrPath = "/apis/certificates.k8s.io/v1/certificatesigningrequests"
const saPath = "/var/run/secrets/kubernetes.io/serviceaccount/"

type inventory map[string]string

type request struct {
	Metadata struct {
		Name              string  `json:"name"`
		DeletionTimestamp *string `json:"deletionTimestamp"`
	} `json:"metadata"`
	Spec struct {
		SignerName        string   `json:"signerName"`
		Username          string   `json:"username"`
		Groups            []string `json:"groups"`
		Usages            []string `json:"usages"`
		Request           []byte   `json:"request"`
		ExpirationSeconds *int64   `json:"expirationSeconds"`
	} `json:"spec"`
	Status struct {
		Certificate string            `json:"certificate"`
		Conditions  []json.RawMessage `json:"conditions"`
	} `json:"status"`
}

type node struct {
	Metadata struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Status struct {
		Addresses []struct {
			Type    string `json:"type"`
			Address string `json:"address"`
		} `json:"addresses"`
	} `json:"status"`
}

func validate(r request, n node, hosts inventory) error {
	name := strings.TrimPrefix(r.Spec.Username, "system:node:")
	ip, known := hosts[name]
	if !known || r.Spec.Username != "system:node:"+name || n.Metadata.Name != name {
		return fmt.Errorf("要求元がノード台帳と一致しません")
	}
	if r.Spec.SignerName != "kubernetes.io/kubelet-serving" ||
		!slices.Equal(sorted(r.Spec.Groups), []string{"system:authenticated", "system:nodes"}) {
		return fmt.Errorf("signer/groups が不正です")
	}
	usages := sorted(r.Spec.Usages)
	if !slices.Equal(usages, []string{"digital signature", "server auth"}) &&
		!slices.Equal(usages, []string{"digital signature", "key encipherment", "server auth"}) {
		return fmt.Errorf("usages が不正です")
	}
	if r.Spec.ExpirationSeconds != nil && (*r.Spec.ExpirationSeconds < 600 || *r.Spec.ExpirationSeconds > 366*86400) {
		return fmt.Errorf("要求有効期間が範囲外です")
	}
	// Node.status はノード自身が更新できるため、台帳の代わりにはしない。
	ips := []string{}
	for _, address := range n.Status.Addresses {
		if address.Type == "InternalIP" {
			ips = append(ips, address.Address)
		}
	}
	if !slices.Equal(ips, []string{ip}) {
		return fmt.Errorf("Node InternalIP が台帳と一致しません")
	}
	block, rest := pem.Decode(r.Spec.Request)
	if block == nil || block.Type != "CERTIFICATE REQUEST" || len(bytes.TrimSpace(rest)) != 0 {
		return fmt.Errorf("CSR PEM が不正です")
	}
	cr, err := x509.ParseCertificateRequest(block.Bytes)
	if err != nil {
		return err
	}
	if err = cr.CheckSignature(); err != nil {
		return err
	}
	if cr.Subject.CommonName != r.Spec.Username || !slices.Equal(cr.Subject.Organization, []string{"system:nodes"}) || len(cr.Subject.Names) != 2 {
		return fmt.Errorf("CSR subject が不正です")
	}
	if !slices.Equal(cr.DNSNames, []string{name}) || len(cr.IPAddresses) != 1 || !cr.IPAddresses[0].Equal(net.ParseIP(ip)) || len(cr.EmailAddresses) != 0 || len(cr.URIs) != 0 {
		return fmt.Errorf("CSR SAN が台帳の DNS/IP と一致しません")
	}
	// x509 が解釈しない GeneralName や追加の拡張も許可しない。
	if len(cr.Extensions) != 1 || !cr.Extensions[0].Id.Equal(asn1.ObjectIdentifier{2, 5, 29, 17}) {
		return fmt.Errorf("SAN 以外の拡張は許可しません")
	}
	var names []asn1.RawValue
	rest, err = asn1.Unmarshal(cr.Extensions[0].Value, &names)
	if err != nil || len(rest) != 0 || len(names) != 2 {
		return fmt.Errorf("SAN 構造が不正です")
	}
	for _, item := range names {
		if item.Class != 2 || item.IsCompound || (item.Tag != 2 && item.Tag != 7) {
			return fmt.Errorf("未知の SAN 種別です")
		}
	}
	return nil
}

func sorted(values []string) []string {
	result := slices.Clone(values)
	slices.Sort(result)
	return result
}

type controller struct {
	client      *http.Client
	baseURL     string
	tokenFile   string
	hosts       inventory
	roots       *x509.CertPool
	mu          sync.RWMutex
	lastSuccess time.Time
	metrics     string
}

func (c *controller) api(method, path string, body []byte, target any) error {
	token, err := os.ReadFile(c.tokenFile) // projected token の更新を毎回反映する。
	if err != nil {
		return err
	}
	req, err := http.NewRequest(method, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("API %s %s: HTTP %d", method, path, resp.StatusCode)
	}
	if target != nil {
		return json.NewDecoder(io.LimitReader(resp.Body, 16<<20)).Decode(target)
	}
	return nil
}

func (c *controller) reconcile() error {
	var list struct {
		Items []json.RawMessage `json:"items"`
	}
	if err := c.api("GET", csrPath+"?fieldSelector=spec.signerName%3Dkubernetes.io%2Fkubelet-serving", nil, &list); err != nil {
		return err
	}
	for _, raw := range list.Items {
		var r request
		if err := json.Unmarshal(raw, &r); err != nil {
			return err
		}
		if r.Spec.SignerName != "kubernetes.io/kubelet-serving" || r.Metadata.DeletionTimestamp != nil || r.Status.Certificate != "" || len(r.Status.Conditions) != 0 {
			continue
		}
		name := strings.TrimPrefix(r.Spec.Username, "system:node:")
		if _, ok := c.hosts[name]; !ok {
			log.Printf("CSR %s: 未登録の要求元を承認しません", r.Metadata.Name)
			continue
		}
		var n node
		if err := c.api("GET", "/api/v1/nodes/"+url.PathEscape(name), nil, &n); err != nil {
			return err
		}
		if err := validate(r, n, c.hosts); err != nil {
			log.Printf("CSR %s: 承認しません: %v", r.Metadata.Name, err)
			continue
		}
		// resourceVersion/UID を保持し、検査後に同名CSRが差し替わった場合はAPI競合で止める。
		var object map[string]any
		if err := json.Unmarshal(raw, &object); err != nil {
			return err
		}
		object["status"] = map[string]any{"conditions": []any{map[string]any{
			"type": "Approved", "status": "True", "reason": "InventoryVerified",
			"message":        "requestor, subject, SAN and Node InternalIP match the Git inventory",
			"lastUpdateTime": time.Now().UTC().Format(time.RFC3339),
		}}}
		body, err := json.Marshal(object)
		if err != nil {
			return err
		}
		if err = c.api("PUT", csrPath+"/"+url.PathEscape(r.Metadata.Name)+"/approval", body, nil); err != nil {
			return err
		}
		log.Printf("CSR %s (%s) を承認しました", r.Metadata.Name, name)
	}
	return nil
}

func (c *controller) probe() string {
	var output strings.Builder
	for name, ip := range c.hosts {
		ok, expires := 0, int64(0)
		certificate, err := probeCertificate(net.JoinHostPort(ip, "10250"), ip, c.roots)
		if err == nil {
			ok, expires = 1, certificate.NotAfter.Unix()
		} else {
			log.Printf("TLS %s: %v", name, err)
		}
		fmt.Fprintf(&output, "kubelet_serving_certificate_valid{node=%q} %d\nkubelet_serving_certificate_expiry_seconds{node=%q} %d\n", name, ok, name, expires)
	}
	return output.String()
}

func probeCertificate(address, serverName string, roots *x509.CertPool) (*x509.Certificate, error) {
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 5 * time.Second}, "tcp", address,
		&tls.Config{RootCAs: roots, ServerName: serverName, MinVersion: tls.VersionTLS12})
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	return conn.ConnectionState().PeerCertificates[0], nil
}

func main() {
	hosts := inventory{}
	data, err := os.ReadFile("/config/nodes.json")
	if err != nil {
		log.Fatal(err)
	}
	if err = json.Unmarshal(data, &hosts); err != nil || len(hosts) == 0 {
		log.Fatal("ノード台帳が不正です")
	}
	seen := map[string]bool{}
	for name, ip := range hosts {
		if name == "" || strings.ContainsAny(name, "/\n\r") || net.ParseIP(ip).To4() == nil || seen[ip] {
			log.Fatal("ノード名/IPが不正または重複しています")
		}
		seen[ip] = true
	}
	ca, err := os.ReadFile(saPath + "ca.crt")
	if err != nil {
		log.Fatal(err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(ca) {
		log.Fatal("クラスタCAが不正です")
	}
	c := &controller{
		client:    &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}}},
		baseURL:   "https://" + net.JoinHostPort(os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")),
		tokenFile: saPath + "token", hosts: hosts, roots: roots,
	}
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		c.mu.RLock()
		defer c.mu.RUnlock()
		if time.Since(c.lastSuccess) > 2*time.Minute {
			http.Error(w, "API reconciliation not ready", 503)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		c.mu.RLock()
		defer c.mu.RUnlock()
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "kubelet_serving_approver_last_success_seconds %d\n%s", c.lastSuccess.Unix(), c.metrics)
	})
	go func() {
		for {
			err := c.reconcile()
			metrics := c.probe()
			c.mu.Lock()
			if err == nil {
				c.lastSuccess = time.Now()
			} else {
				log.Print(err)
			}
			c.metrics = metrics
			c.mu.Unlock()
			time.Sleep(30 * time.Second)
		}
	}()
	server := &http.Server{Addr: ":8080", ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(server.ListenAndServe())
}
