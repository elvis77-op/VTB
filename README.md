# VM Trusted Bootup
For multi-party collaboration scenarios, VTB (VM Trusted Bootup) allows a previewed open-sourced workload to be launched inside TDVM after all parties agree upon the trustiness of a customized work flow pre-loaded in Initrd/Initramfs. It is worth noting that VTB relies on TDX and RTMR check mechanism to achieve this goal.

## Overview

There is an existing project: [Full Disk Encryption](https://github.com/cc-api/full-disk-encryption/blob/main), which implemented a method to first decrypt and then load an encrypted disk image in a TDVM. VTB revises the procedure by allowing a previewed open-sourced workload to be trusted and bootup in a TDVM. The reason why unencrypted OS images are needed is because for multi-party scenarios, encrypted OS images are black boxes that no other parties than the image owners can sit assured that they are trusted. Our method mainly refers to the design idea in chapter 14.4.2 in [Intel&reg; TDX Virtual Firmware Design Guide](https://www.intel.com/content/www/us/en/content-details/733585/intel-tdx-virtual-firmware-design-guide.html). It showcases how an open-sourced OS image is launched in a TDVM, which is trusted by all parties. 


### Key Features

- TDX for security
- RTMR generation and measurement
- Intel&reg; Appraisal Engine
- Build Initrd codes and generate expected RTMR values
- Attestation service for verification
- Hashing mechanisms

## Architechture
![Architecture.png](images/architecture.png)


## System Flow
### Open-sourced OS image Preparation
```mermaid
sequenceDiagram
    participant GH as VTB Github Portal
    participant CR as Public Clean Room
    actor P-1 as Party One
    actor P-2 as Party Two
    actor PR as Public Reviewers
    Note over GH: Upload a sample OS image containing: <br>1. the data partition disk with a customized TDX attestation service <br>2. Initrd Codes with attestation agent and hashing agent
	GH->>P-1: Download OS image
	Note over P-1: Review and may modify OS image
	GH->>P-2: Download OS image
	Note over P-2: Review and may modify OS image
	Note over PR: If necessary, all parties invite Public Reviewers to <br>further review OS image including Initrd codes
    PR->>CR: Once approved, OS image is <br>sent over to clean room for storage
	Note over CR: OS image is stored for public download
    
```

### VM Trusted Bootup via Trusted Initrd Codes
```mermaid
sequenceDiagram
    box rgba(19, 9, 137, 0.5) TDX VM
      participant IR as Initrd Codes
    end
    participant P-1 as Party One Attestation Service
    participant P-2 as Party Two Attestation Service
    participant CR as Clean Room
    actor ADMIN as Operator

    rect rgba(230,230,230,0.5)
        Note over P-1: Start Attestation Service with <br> URL as U-P-1 and certificate as C-P-1
        P-1->>ADMIN: Send U-P-1 and C-P-1
        Note over P-2: Start Attestation Service with <br> URL as U-P-2 and certificate as C-P-2
        P-2->>ADMIN: Send U-P-2 and C-P-2
        CR->>ADMIN: Pre-approved OS image is sent
        Note over ADMIN: Get OS image from clean room, <br>merge URLs and Certificates into Initrd,<br> and get the merged OS image
        ADMIN->>P-1: Send the merged OS image
        Note over P-1: Calculate data partition disk's hash <br>and expected RTMR in indirect/grub boot mode
        ADMIN->>P-2: Send the merged OS image
	    Note over P-2: Calculate data partition disk's hash <br>and expected RTMR in indirect/grub boot mode
        ADMIN->>IR: Merged OS image is transferred to TDX VM
	    Note over ADMIN: Run OS image in indirect/grub mode
        Note over IR: In early-boot stage, <br>Initrd attestation agent is triggered
        Note over IR: Generate a signing key pair IR-key-pair.<br> Via gRPC, requests quote verification with party one
        IR->>P-1: 
        Note over P-1: Challenge with nonce
        P-1->>IR:
        Note over IR: Generate and send quote with nonce <br>and IR-key-pair public key in reportdata 
	    IR->>P-1: 
        Note over P-1: Verify quote against expected RTMR with <br>Intel#174; QAL and send back result as OK and <br>the expected hash locally calculated, <br>both signed by P-1's private key
	    P-1->>IR: Signed result and expected hash value
	    Note over IR: Verify result and hash by using <br>P-1's public key in C-P-1, <br>and continue the verification with P-2
	IR<<->>P-2: Same procedure as that of P-1
	Note over IR: Once hashes from both P-1 and P-2 are the same, <br>the hash can be considered as the expected hash. <br>It also means both parties agree Initrd codes are trusted. <br>Hashing agent begins to calculate the loaded data partition disk's <br>hash and compare it with the expected one. If OK, <br>then hashing agent ends Initrd session by switching to data partition disk
    Note over IR: By now, data partition disk is launched, <br>together with the customized attestation service, <br>which is trusted by all parties
    end	 
    
```

## Prerequisites

- Intel CPU with SGX and TDX support
- DCAP driver and related software stack
- Linux environment (this project has worked successfully with Ubuntu 22.04 LTS)

## Preamble
1. You need at least one host to operate with:
    Host A: meets the [prerequisites](#prerequisites)


## Usage



## Current Phase
- [x] Basic build up of Initrd codes inclusing attestation agent, gRPC, and hashing agent
- [x] Basic quote verification via gRPC
  
## Future Work
- [x] Finish the codes for each party's attestation service
- [x] Finish the whole VTB process

### Security Enhancements
- [x] Validate RTMR value changes when Initrd codes are changed
- [x] Evaluate whether the hashing agent can ensure data partition disk is correctly hashed and intact during bootup
  
### Architectural Improvements
- [x] Use TDVF CFV to configure and preload all parties' URLs and Certificates
- [x] Use RA-TLS for quote verification


## Design Considerations for Future Versions

### Current Limitations