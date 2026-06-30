// utils.h
#ifndef UTILS_H
#define UTILS_H

#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <cstring>
#include <memory>
#include <cstdint>

#include <openssl/sha.h>
#include <openssl/rsa.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>

namespace attestation {
namespace utils {

class CryptoUtils {
public:
    static std::string GetFileHash(const std::string& file_path, 
                                   std::string* error_msg = nullptr);
    
    static std::string GetDataHash(const void* data, size_t size);

    static int64_t GetFileSize(const std::string& file_path);

    static bool FileExists(const std::string& file_path);

    static std::vector<std::string> ListBlockDevices();

    static std::string GenerateNonce(size_t length = 32);

    static std::vector<uint8_t> GenerateNonceBytes(size_t length = 32);

    static bool GenerateRSAKeyPair(int key_size,
                                   std::string& public_key_pem,
                                   std::string& private_key_pem);
    
    static bool GenerateRSAKeyPair(std::string& public_key_pem,
                                   std::string& private_key_pem);

    static bool RSASign(const std::string& data,
                        const std::string& private_key_pem,
                        std::vector<uint8_t>& signature);

    static bool RSASignBase64(const std::string& data,
                              const std::string& private_key_pem,
                              std::string& signature_b64);

    static bool RSAVerify(const std::string& data,
                          const std::vector<uint8_t>& signature,
                          const std::string& public_key_pem);
    
    static bool RSAVerifyBase64(const std::string& data,
                                const std::string& signature_b64,
                                const std::string& public_key_pem);

    static std::string BytesToString(const std::vector<uint8_t>& data);
    static std::string BytesToString(const uint8_t* data, size_t length);
    
    static std::vector<uint8_t> StringToBytes(const std::string& str);
    
    static std::string BytesToHex(const std::vector<uint8_t>& data);
    static std::string BytesToHex(const uint8_t* data, size_t length);

    static std::vector<uint8_t> HexToBytes(const std::string& hex);

private:
    static constexpr size_t BUFFER_SIZE = 8192;
};

using SHA256 = CryptoUtils;

} // namespace utils
} // namespace attestation

#endif // SHA256_UTILS_H