/*
 *
 * Copyright 2015 gRPC authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#include <grpcpp/grpcpp.h>

#include <iostream>
#include <memory>
#include <string>

#include "attestation_service.grpc.pb.h"
#include "tdx_attest.h"
#include "utils.h"

using grpc::Channel;
using grpc::ClientContext;
using grpc::Status;

using attestation::v1::AttestationService;
using attestation::v1::ChallengeReply;
using attestation::v1::ChallengeRequest;
using attestation::v1::QuoteVerificationReply;
using attestation::v1::QuoteVerificationRequest;

using attestation::utils::CryptoUtils;


#define devname		"/dev/tdx-attest"


int GetQuote(const std::string& nonce, const std::string& pubkey_hash, std::vector<uint8_t>& quote_data_) {
    uint32_t quote_size = 0;
    tdx_report_data_t report_data = {{0}};
    tdx_report_t tdx_report = {{0}};
    tdx_uuid_t selected_att_key_id = {0};
    uint8_t *p_quote_buf = NULL;
    std::string report_data_hex_;

    std::vector<uint8_t> nonce_bytes = CryptoUtils::HexToBytes(nonce);
    nonce_bytes.resize(32, 0);
    
    std::vector<uint8_t> hash_bytes = CryptoUtils::HexToBytes(pubkey_hash);
    hash_bytes.resize(32, 0);

    for (int i = 0; i < 32 && i < nonce_bytes.size(); i++) {
        report_data.d[i] = nonce_bytes[i];
    }
    for (int i = 0; i < 32 && i < hash_bytes.size(); i++) {
        report_data.d[32 + i] = hash_bytes[i];
    }

    report_data_hex_ = CryptoUtils::BytesToHex(report_data.d, sizeof(report_data.d));
    std::cout << "Report data (64 bytes): " << report_data_hex_ << std::endl;

    if (TDX_ATTEST_SUCCESS != tdx_att_get_report(&report_data, &tdx_report)) {
        std::cerr << "Failed to get the TDX report" << std::endl;
        return 1;
    }
    std::cout << "TDX Report generated successfully" << std::endl;

    if (TDX_ATTEST_SUCCESS != tdx_att_get_quote(&report_data, NULL, 0, 
        &selected_att_key_id, &p_quote_buf, &quote_size, 0)) {
        std::cerr << "Failed to get the TDX quote" << std::endl;
        return 1;
    }

    std::cout << "TDX Quote generated successfully" << std::endl;
    std::cout << "Quote size: " << quote_size << " bytes" << std::endl;

    quote_data_.assign(p_quote_buf, p_quote_buf + quote_size);

    tdx_att_free_quote(p_quote_buf);

    return 0;
}
// ===== Client =====
class AttestationClient {
 public:
  explicit AttestationClient(std::shared_ptr<Channel> channel)
      : stub_(AttestationService::NewStub(channel)) {}

  std::string RequestChallenge(const std::string& user) {
    ChallengeRequest request;
    request.set_name(user);

    ChallengeReply reply;
    ClientContext context;

    Status status = stub_->Challenge(&context, request, &reply);

    if (status.ok()) {
      return reply.nonce();
    } else {
      std::cout << status.error_code() << ": "
                << status.error_message() << std::endl;
      return "RPC failed";
    }
  }

  std::string SendQuote(const std::string& quote_b64, const std::string& public_key_pem, const std::string& guest_image_hash) {
    QuoteVerificationRequest request;
    request.set_quote(quote_b64);
    request.set_public_key(public_key_pem);
    request.set_hash(guest_image_hash);

    QuoteVerificationReply reply;
    ClientContext context;

    Status status =
        stub_->QuoteVerification(&context, request, &reply);

    if (status.ok()) {
      return reply.result();
    } else {
      return "Quote verification failed";
    }
  }

 private:
  std::unique_ptr<AttestationService::Stub> stub_;
};

// ===== main =====
int main(int argc, char** argv) {
  std::string target_str = "127.0.0.1:50051";
  std::string public_key_pem;
  std::string private_key_pem;
  std::vector<uint8_t> quote_data;

  AttestationClient client(
      grpc::CreateChannel(target_str,
                          grpc::InsecureChannelCredentials()));

  std::string user = "initrd_01";

  std::string nonce = client.RequestChallenge(user);
  std::cout << "Received nonce: " << nonce << std::endl;

  if (!CryptoUtils::GenerateRSAKeyPair(public_key_pem, private_key_pem)) {
    std::cerr << "Failed to generate RSA key pair" << std::endl;
    return 1;
  }
  std::cout << "RSA key pair generated successfully" << std::endl;

  std::string pubkey_hash = CryptoUtils::GetDataHash(
      public_key_pem.c_str(), public_key_pem.length());
  std::cout << "Public key hash: " << pubkey_hash << std::endl;

  if (GetQuote(nonce, pubkey_hash, quote_data) != 0) {
    std::cerr << "Failed to get TDX quote" << std::endl;
    return 1;
  }

  std::string quote_b64 = CryptoUtils::BytesToString(quote_data);
  std::cout << "Quote Base64 length: " << quote_b64.length() << std::endl;

  std::string guest_image_hash = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a3b4c5d6a7b8c9d0";
  std::cout << "Guest image hash: " << guest_image_hash << std::endl;

  std::string result = client.SendQuote(quote_b64, public_key_pem, guest_image_hash);
  std::cout << "Verification result: " << result << std::endl;

  return 0;
}
