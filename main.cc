#include <memory>
#include <vector>

#include "grpc/grpc.h"
#include "grpcpp/generic/async_generic_service.h"
#include "grpcpp/security/credentials.h"
#include "grpcpp/server.h"
#include "grpcpp/server_builder.h"

int main(int argc, char** argv) {
  ::grpc::ServerBuilder builder;

  builder.AddListeningPort(
      "unix:tmp.sock",
      grpc::InsecureServerCredentials());

  auto service = std::make_unique<::grpc::AsyncGenericService>();

  builder.RegisterAsyncGenericService(service.get());

  std::vector<std::unique_ptr<::grpc::ServerCompletionQueue>> cqs;

  cqs.push_back(builder.AddCompletionQueue());

  std::unique_ptr<::grpc::Server> server = builder.BuildAndStart();

  return 0;
}
