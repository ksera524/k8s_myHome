package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/json"
	"encoding/pem"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T, change func(*request, *x509.CertificateRequest, *node)) (request, node, inventory) {
	t.Helper()
	var r request
	r.Metadata.Name = "csr-test"
	r.Spec.Username = "system:node:k8s-worker1"
	r.Spec.SignerName = "kubernetes.io/kubelet-serving"
	r.Spec.Groups = []string{"system:nodes", "system:authenticated"}
	r.Spec.Usages = []string{"digital signature", "server auth"}
	cr := &x509.CertificateRequest{
		Subject:  pkix.Name{CommonName: r.Spec.Username, Organization: []string{"system:nodes"}},
		DNSNames: []string{"k8s-worker1"}, IPAddresses: []net.IP{net.ParseIP("192.168.122.11")},
	}
	var n node
	if err := json.Unmarshal([]byte(`{"metadata":{"name":"k8s-worker1"},"status":{"addresses":[{"type":"InternalIP","address":"192.168.122.11"}]}}`), &n); err != nil {
		t.Fatal(err)
	}
	if change != nil {
		change(&r, cr, &n)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.CreateCertificateRequest(rand.Reader, cr, key)
	if err != nil {
		t.Fatal(err)
	}
	r.Spec.Request = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE REQUEST", Bytes: der})
	return r, n, inventory{"k8s-worker1": "192.168.122.11", "k8s-worker2": "192.168.122.12"}
}

func TestValidRequests(t *testing.T) {
	for _, renewal := range []bool{false, true} {
		r, n, hosts := fixture(t, nil)
		if renewal {
			r.Spec.Usages = append(r.Spec.Usages, "key encipherment")
		}
		if err := validate(r, n, hosts); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRejectForgedRequests(t *testing.T) {
	cases := map[string]func(*request, *x509.CertificateRequest, *node){
		"unknown node": func(r *request, c *x509.CertificateRequest, n *node) { r.Spec.Username = "system:node:evil" },
		"wrong signer": func(r *request, c *x509.CertificateRequest, n *node) {
			r.Spec.SignerName = "kubernetes.io/kube-apiserver-client-kubelet"
		},
		"admin group": func(r *request, c *x509.CertificateRequest, n *node) {
			r.Spec.Groups = append(r.Spec.Groups, "system:masters")
		},
		"client usage": func(r *request, c *x509.CertificateRequest, n *node) {
			r.Spec.Usages = append(r.Spec.Usages, "client auth")
		},
		"missing usage": func(r *request, c *x509.CertificateRequest, n *node) { r.Spec.Usages = nil },
		"duplicate usage": func(r *request, c *x509.CertificateRequest, n *node) {
			r.Spec.Usages = append(r.Spec.Usages, "server auth")
		},
		"long expiry": func(r *request, c *x509.CertificateRequest, n *node) {
			v := int64(367 * 86400)
			r.Spec.ExpirationSeconds = &v
		},
		"wrong CN": func(r *request, c *x509.CertificateRequest, n *node) {
			c.Subject.CommonName = "system:node:k8s-worker2"
		},
		"wrong organization": func(r *request, c *x509.CertificateRequest, n *node) {
			c.Subject.Organization = []string{"system:masters"}
		},
		"extra subject": func(r *request, c *x509.CertificateRequest, n *node) {
			c.Subject.OrganizationalUnit = []string{"extra"}
		},
		"other IP": func(r *request, c *x509.CertificateRequest, n *node) {
			c.IPAddresses = []net.IP{net.ParseIP("192.168.122.12")}
		},
		"other DNS": func(r *request, c *x509.CertificateRequest, n *node) { c.DNSNames = []string{"k8s-worker2"} },
		"extra DNS": func(r *request, c *x509.CertificateRequest, n *node) {
			c.DNSNames = append(c.DNSNames, "attacker.example")
		},
		"IP only":  func(r *request, c *x509.CertificateRequest, n *node) { c.DNSNames = nil },
		"DNS only": func(r *request, c *x509.CertificateRequest, n *node) { c.IPAddresses = nil },
		"email":    func(r *request, c *x509.CertificateRequest, n *node) { c.EmailAddresses = []string{"root@example.com"} },
		"URI": func(r *request, c *x509.CertificateRequest, n *node) {
			u, _ := url.Parse("https://example.com")
			c.URIs = []*url.URL{u}
		},
		"CA extension": func(r *request, c *x509.CertificateRequest, n *node) {
			c.ExtraExtensions = []pkix.Extension{{Id: asn1.ObjectIdentifier{2, 5, 29, 19}, Value: []byte{48, 0}}}
		},
		"node status forged": func(r *request, c *x509.CertificateRequest, n *node) {
			n.Status.Addresses[0].Address = "192.168.122.12"
			c.IPAddresses = []net.IP{net.ParseIP("192.168.122.12")}
		},
	}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			r, n, hosts := fixture(t, change)
			if validate(r, n, hosts) == nil {
				t.Fatal("不正CSRが承認対象になりました")
			}
		})
	}
	t.Run("bad signature", func(t *testing.T) {
		r, n, hosts := fixture(t, nil)
		block, _ := pem.Decode(r.Spec.Request)
		block.Bytes[len(block.Bytes)-1] ^= 1
		r.Spec.Request = pem.EncodeToMemory(block)
		if validate(r, n, hosts) == nil {
			t.Fatal("署名改変を検知しませんでした")
		}
	})
	t.Run("trailing PEM", func(t *testing.T) {
		r, n, hosts := fixture(t, nil)
		r.Spec.Request = append(r.Spec.Request, r.Spec.Request...)
		if validate(r, n, hosts) == nil {
			t.Fatal("複数CSRが受理されました")
		}
	})
}

func TestReconcileApprovalAndTokenRotation(t *testing.T) {
	r, n, hosts := fixture(t, nil)
	raw, _ := json.Marshal(r)
	var object map[string]any
	json.Unmarshal(raw, &object)
	object["metadata"].(map[string]any)["uid"] = "original-uid"
	object["metadata"].(map[string]any)["resourceVersion"] = "42"
	tokenFile := filepath.Join(t.TempDir(), "token")
	os.WriteFile(tokenFile, []byte("initial"), 0600)
	approvals := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		token, _ := os.ReadFile(tokenFile)
		if req.Header.Get("Authorization") != "Bearer "+string(token) {
			t.Error("token未更新")
		}
		switch {
		case req.Method == "GET" && req.URL.Path == csrPath:
			json.NewEncoder(w).Encode(map[string]any{"items": []any{object}})
		case req.Method == "GET" && strings.HasPrefix(req.URL.Path, "/api/v1/nodes/"):
			json.NewEncoder(w).Encode(n)
		case req.Method == "PUT":
			var updated map[string]any
			json.NewDecoder(req.Body).Decode(&updated)
			meta := updated["metadata"].(map[string]any)
			if meta["resourceVersion"] != "42" || meta["uid"] != "original-uid" {
				t.Error("CSRの同一性が保持されていません")
			}
			object = updated
			approvals++
			w.WriteHeader(200)
		default:
			t.Error(req.URL)
			w.WriteHeader(404)
		}
	}))
	defer server.Close()
	c := controller{client: server.Client(), baseURL: server.URL, tokenFile: tokenFile, hosts: hosts}
	if err := c.reconcile(); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(tokenFile, []byte("rotated"), 0600)
	if err := c.reconcile(); err != nil {
		t.Fatal(err)
	}
	if approvals != 1 {
		t.Fatalf("既承認CSRを再承認しました: %d", approvals)
	}
}

func TestReconcileNeverApprovesInvalidCSR(t *testing.T) {
	r, n, hosts := fixture(t, func(r *request, c *x509.CertificateRequest, n *node) {
		c.IPAddresses = []net.IP{net.ParseIP("192.168.122.12")}
	})
	tokenFile := filepath.Join(t.TempDir(), "token")
	os.WriteFile(tokenFile, []byte("test"), 0600)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.Method != "GET" {
			t.Error("不正CSRに書き込みました")
			w.WriteHeader(500)
			return
		}
		if req.URL.Path == csrPath {
			json.NewEncoder(w).Encode(map[string]any{"items": []request{r}})
		} else {
			json.NewEncoder(w).Encode(n)
		}
	}))
	defer server.Close()
	c := controller{client: server.Client(), baseURL: server.URL, tokenFile: tokenFile, hosts: hosts}
	if err := c.reconcile(); err != nil {
		t.Fatal(err)
	}
}

func TestTLSRequiresTrustedCAAndMatchingIP(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer server.Close()
	roots := x509.NewCertPool()
	roots.AddCert(server.Certificate())
	address := strings.TrimPrefix(server.URL, "https://")
	if _, err := probeCertificate(address, "127.0.0.1", roots); err != nil {
		t.Fatal(err)
	}
	if _, err := probeCertificate(address, "127.0.0.1", x509.NewCertPool()); err == nil {
		t.Fatal("未信頼CAを受理しました")
	}
	if _, err := probeCertificate(address, "192.168.122.11", roots); err == nil {
		t.Fatal("IP SAN不一致を受理しました")
	}
}
