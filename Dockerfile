FROM alpine:latest
RUN echo "Hello from k8s_myHome slack.rs test image" > /hello.txt
CMD ["cat", "/hello.txt"]# Test Harbor push from k8s-myhome-runners
