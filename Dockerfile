FROM alpine:latest

# Test Harbor push from k8s-myhome-runners
# Harbor push test - 2025年  8月 10日 土曜日
RUN echo "Hello from k8s_myHome test image - $(date)" > /hello.txt

CMD ["cat", "/hello.txt"]
