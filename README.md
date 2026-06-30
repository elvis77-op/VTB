# VM Trusted Bootup
To achieve verifiable transparency, VTB (VM Trusted Bootup) enables a pre-reviewed, open-source workload to be launched inside a TDVM after a trusted verifier has confirmed the authenticity and integrity of a customized workflow pre-loaded in Initrd/Initramfs. It is worth noting that VTB leverages TDX and RTMR measurements to accomplish this goal.

## Overview

This method primarily draws from the design concepts outlined in Section 14.4.2 of [Intel&reg; TDX Virtual Firmware Design Guide](https://www.intel.com/content/www/us/en/content-details/733585/intel-tdx-virtual-firmware-design-guide.html). Rather than launching an encrypted OS image, this method demonstrates how an open-source OS image is launched within a TDVM, where its authenticity is verified by a trusted verifier to ensure a verifiable launch process. 


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
    actor P-1 as Trusted Verifier
    actor PR as Public Reviewers
    Note over GH: In the portal, a sample OS image containing: <br>1. Initrd with attestation agent and hashing agent<br>2. Root partition with a sample previewed workload
	GH->>P-1: Download OS image
	Note over P-1: Review and may modify OS image
	Note over PR: If necessary, may invite Public Reviewers to <br>further review OS image including Initrd codes
    PR->>CR: Once approved, OS image is <br>sent over to clean room for storage
	Note over CR: OS image is stored for public download
    
```

### VM Trusted Bootup via Trusted Initrd Codes
```mermaid
sequenceDiagram
    box rgba(19, 9, 137, 0.5) TDX VM
      participant IC as Initrd Codes
    end
    participant P-1 as Verifier's Attestation Service
    participant CR as Clean Room
    actor ADMIN as Operator

    rect rgba(230,230,230,0.5)
        Note over P-1: Start Attestation Service with <br> URL as Url-V and certificate as Cert-V
        P-1->>ADMIN: Send Url-V and Cert-V
        CR->>ADMIN: Pre-approved OS image is sent
        Note over ADMIN: Get OS image from clean room, <br>merge Url-V and Cert-V into Initrd,<br> and get the merged OS image
        ADMIN->>P-1: Send the merged OS image
        Note over P-1: Calculate root partition's hash Hash-Expected and <br>image's expected RTMR RTMR-Expected in indirect/grub boot mode
        ADMIN->>IC: Merged OS image is transferred to TDX VM
	    Note over ADMIN: Run OS image in indirect/grub mode
        Note over IC: In early-boot stage, <br>Initrd attestation agent triggeres quote verification<br>with Verifier by looking at Url-V
        Note over IC: 1. Generate a signing key pair IC-key-pair<br>2. Calculate root partition's hash RP-hash<br>Via gRPC, requests quote verification with the Verifier
        IC->>P-1: 
        Note over P-1: Challenge with nonce
        P-1->>IC:
        Note over IC: 1. Use IC-key-pair private key to sign RP-hash and nonce <br>2. Generate quote with nonce, IC-hash, <br>and IC-key-pair public key in reportdata 
	    IC->>P-1: Send quote, signed IC-hash, IC-key-pair certificate
        Note over P-1: 1. Verify quote against RTMR-Expected by using Intel#174; QAL <br>2. Compare IC-hash with Hash-Expected <br>If OK, sign result as OK by using Verifier's private key  
	    P-1->>IC: Signed result
	    Note over IC: Verify result by using Verifier's public key in Cert-V
        Note over IC: When verifying the result as OK, it means <br> Verifier agrees both Initrd and root partition are authenticated. 
    Note over IC: Hashing agent ends Initrd session by switching to root partition 
    Note over IC: By now, previewed workload is launched and trusted by the Verifier
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
- [ ] Finish the codes for Verifier's attestation service
- [ ] Finish the whole VTB process

### Security Enhancements
- [ ] Validate RTMR value changes when Initrd codes are changed
- [ ] Evaluate whether the hashing agent can ensure data partition disk is correctly hashed and intact during bootup
  
### Architectural Improvements
- [ ] Use TDVF CFV to configure and preload Verifier's URL and Certificate
- [ ] Use RA-TLS for quote verification


## Design Considerations for Future Versions

### Current Limitations