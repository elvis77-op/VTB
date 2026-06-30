// utils.cc
#include "utils.h"
#include <iostream>
#include <algorithm>

namespace attestation {
namespace utils {

std::string CryptoUtils::GetFileHash(const std::string& file_path, 
                                     std::string* error_msg) {
    std::ifstream file(file_path, std::ios::binary);
    if (!file.is_open()) {
        if (error_msg) {
            *error_msg = "Cannot open file: " + file_path;
        }
        return "";
    }

    SHA256_CTX sha256;
    SHA256_Init(&sha256);

    std::vector<char> buffer(BUFFER_SIZE);
    
    while (file.read(buffer.data(), buffer.size()) || file.gcount() > 0) {
        SHA256_Update(&sha256, buffer.data(), file.gcount());
        if (file.eof()) break;
    }

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_Final(hash, &sha256);

    return BytesToHex(hash, SHA256_DIGEST_LENGTH);
}

std::string CryptoUtils::GetDataHash(const void* data, size_t size) {
    if (!data || size == 0) {
        return "";
    }

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, data, size);
    SHA256_Final(hash, &sha256);
    return BytesToHex(hash, SHA256_DIGEST_LENGTH);
}

int64_t CryptoUtils::GetFileSize(const std::string& file_path) {
    std::ifstream file(file_path, std::ios::binary | std::ios::ate);
    if (file.is_open()) {
        return file.tellg();
    }
    return -1;
}

bool CryptoUtils::FileExists(const std::string& file_path) {
    std::ifstream f(file_path);
    return f.good();
}

std::vector<std::string> CryptoUtils::ListBlockDevices() {
    std::vector<std::string> devices;
    std::ifstream partitions("/proc/partitions");
    std::string line;
    
    // 跳过表头
    if (!std::getline(partitions, line)) return devices;
    if (!std::getline(partitions, line)) return devices;
    
    while (std::getline(partitions, line)) {
        std::istringstream iss(line);
        int major, minor;
        long blocks;
        std::string name;
        
        if (iss >> major >> minor >> blocks >> name) {
            devices.push_back("/dev/" + name);
        }
    }
    return devices;
}

std::string CryptoUtils::GenerateNonce(size_t length) {
    std::vector<uint8_t> nonce_bytes = GenerateNonceBytes(length);
    return BytesToHex(nonce_bytes);
}

std::vector<uint8_t> CryptoUtils::GenerateNonceBytes(size_t length) {
    std::vector<uint8_t> nonce(length);
    if (RAND_bytes(nonce.data(), length) != 1) {
        return std::vector<uint8_t>();
    }
    return nonce;
}

bool CryptoUtils::GenerateRSAKeyPair(int key_size,
                                     std::string& public_key_pem,
                                     std::string& private_key_pem) {
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nullptr);
    if (!ctx) {
        return false;
    }
    
    EVP_PKEY* pkey = nullptr;
    bool success = false;
    
    do {
        if (EVP_PKEY_keygen_init(ctx) <= 0) break;
        if (EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, key_size) <= 0) break;
        if (EVP_PKEY_keygen(ctx, &pkey) <= 0) break;
        
        BIO* pub_bio = BIO_new(BIO_s_mem());
        if (!pub_bio) break;
        if (PEM_write_bio_PUBKEY(pub_bio, pkey) != 1) {
            BIO_free(pub_bio);
            break;
        }
        
        char* pub_data = nullptr;
        long pub_len = BIO_get_mem_data(pub_bio, &pub_data);
        public_key_pem.assign(pub_data, pub_len);
        BIO_free(pub_bio);
        
        BIO* priv_bio = BIO_new(BIO_s_mem());
        if (!priv_bio) break;
        if (PEM_write_bio_PrivateKey(priv_bio, pkey, nullptr, nullptr, 0, nullptr, nullptr) != 1) {
            BIO_free(priv_bio);
            break;
        }
        
        char* priv_data = nullptr;
        long priv_len = BIO_get_mem_data(priv_bio, &priv_data);
        private_key_pem.assign(priv_data, priv_len);
        BIO_free(priv_bio);
        
        success = true;
    } while (false);
    
    if (pkey) EVP_PKEY_free(pkey);
    EVP_PKEY_CTX_free(ctx);
    
    return success;
}

bool CryptoUtils::GenerateRSAKeyPair(std::string& public_key_pem,
                                     std::string& private_key_pem) {
    return GenerateRSAKeyPair(2048, public_key_pem, private_key_pem);
}


bool CryptoUtils::RSASign(const std::string& data,
                          const std::string& private_key_pem,
                          std::vector<uint8_t>& signature) {
    BIO* bio = BIO_new_mem_buf(private_key_pem.c_str(), -1);
    if (!bio) return false;
    
    EVP_PKEY* pkey = PEM_read_bio_PrivateKey(bio, nullptr, nullptr, nullptr);
    BIO_free(bio);
    
    if (!pkey) return false;

    EVP_MD_CTX* md_ctx = EVP_MD_CTX_new();
    if (!md_ctx) {
        EVP_PKEY_free(pkey);
        return false;
    }
    
    bool success = false;
    do {
        if (EVP_DigestSignInit(md_ctx, nullptr, EVP_sha256(), nullptr, pkey) <= 0) break;
        if (EVP_DigestSignUpdate(md_ctx, data.c_str(), data.length()) <= 0) break;

        size_t sig_len = 0;
        if (EVP_DigestSignFinal(md_ctx, nullptr, &sig_len) <= 0) break;
        
        signature.resize(sig_len);
        if (EVP_DigestSignFinal(md_ctx, signature.data(), &sig_len) <= 0) break;
        
        signature.resize(sig_len);
        success = true;
    } while (false);
    
    EVP_MD_CTX_free(md_ctx);
    EVP_PKEY_free(pkey);
    
    return success;
}

bool CryptoUtils::RSASignBase64(const std::string& data,
                                const std::string& private_key_pem,
                                std::string& signature_b64) {
    std::vector<uint8_t> signature;
    if (!RSASign(data, private_key_pem, signature)) {
        return false;
    }
    signature_b64 = BytesToString(signature);
    return true;
}

bool CryptoUtils::RSAVerify(const std::string& data,
                            const std::vector<uint8_t>& signature,
                            const std::string& public_key_pem) {
    BIO* bio = BIO_new_mem_buf(public_key_pem.c_str(), -1);
    if (!bio) return false;
    
    EVP_PKEY* pkey = PEM_read_bio_PUBKEY(bio, nullptr, nullptr, nullptr);
    BIO_free(bio);
    
    if (!pkey) return false;

    EVP_MD_CTX* md_ctx = EVP_MD_CTX_new();
    if (!md_ctx) {
        EVP_PKEY_free(pkey);
        return false;
    }
    
    bool success = false;
    do {
        if (EVP_DigestVerifyInit(md_ctx, nullptr, EVP_sha256(), nullptr, pkey) <= 0) break;
        if (EVP_DigestVerifyUpdate(md_ctx, data.c_str(), data.length()) <= 0) break;
        
        int result = EVP_DigestVerifyFinal(md_ctx, signature.data(), signature.size());
        success = (result == 1);
    } while (false);
    
    EVP_MD_CTX_free(md_ctx);
    EVP_PKEY_free(pkey);
    
    return success;
}

bool CryptoUtils::RSAVerifyBase64(const std::string& data,
                                  const std::string& signature_b64,
                                  const std::string& public_key_pem) {
    std::vector<uint8_t> signature = StringToBytes(signature_b64);
    if (signature.empty()) {
        return false;
    }
    return RSAVerify(data, signature, public_key_pem);
}

std::string CryptoUtils::BytesToString(const std::vector<uint8_t>& data) {
    return BytesToString(data.data(), data.size());
}

std::string CryptoUtils::BytesToString(const uint8_t* data, size_t length) {
    if (!data || length == 0) {
        return "";
    }

    BIO* b64 = BIO_new(BIO_f_base64());
    BIO* bmem = BIO_new(BIO_s_mem());
    b64 = BIO_push(b64, bmem);

    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    
    BIO_write(b64, data, length);
    BIO_flush(b64);
    
    char* encoded_data = nullptr;
    long encoded_len = BIO_get_mem_data(bmem, &encoded_data);
    
    std::string result(encoded_data, encoded_len);
    
    BIO_free_all(b64);
    
    return result;
}

std::vector<uint8_t> CryptoUtils::StringToBytes(const std::string& str) {
    if (str.empty()) {
        return std::vector<uint8_t>();
    }

    BIO* b64 = BIO_new(BIO_f_base64());
    BIO* bmem = BIO_new_mem_buf(str.c_str(), str.length());
    b64 = BIO_push(b64, bmem);

    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    
    std::vector<uint8_t> decoded(str.length());
    int decoded_len = BIO_read(b64, decoded.data(), str.length());
    
    if (decoded_len <= 0) {
        BIO_free_all(b64);
        return std::vector<uint8_t>();
    }
    
    decoded.resize(decoded_len);
    BIO_free_all(b64);
    
    return decoded;
}

std::string CryptoUtils::BytesToHex(const std::vector<uint8_t>& data) {
    return BytesToHex(data.data(), data.size());
}

std::string CryptoUtils::BytesToHex(const uint8_t* data, size_t length) {
    std::ostringstream oss;
    for (size_t i = 0; i < length; i++) {
        oss << std::hex << std::setw(2) << std::setfill('0') 
            << static_cast<int>(data[i]);
    }
    return oss.str();
}

std::vector<uint8_t> CryptoUtils::HexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byte_str = hex.substr(i, 2);
        uint8_t byte = static_cast<uint8_t>(std::stoul(byte_str, nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

} // namespace utils
} // namespace attestation