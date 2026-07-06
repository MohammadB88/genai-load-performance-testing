# LLM Performance Testing & Sizing Guide

## Table of Contents

- [1. Executive Summary](#1-executive-summary)
  - [1.1 Goals & Objectives](#11-goals--objectives)
  - [1.2 Business Value](#12-business-value)
  - [1.3 High-Level Process Overview](#13-high-level-process-overview)
- [2. Technical Overview](#2-technical-overview)
  - [2.1 Architecture Overview](#21-architecture-overview)
  - [2.2 Testing Methodology](#22-testing-methodology)
  - [2.3 Key Technical Concepts](#23-key-technical-concepts)
  - [2.4 Technology Stack](#24-technology-stack)
- [3. Prerequisites & Environment Setup](#3-prerequisites--environment-setup)
  - [3.1 Infrastructure Requirements](#31-infrastructure-requirements)
  - [3.2 Software Requirements](#32-software-requirements)
  - [3.3 Access Requirements](#33-access-requirements)
  - [3.4 Configuration Management](#34-configuration-management)
  - [3.5 Quick Environment Verification](#35-quick-environment-verification)
  - [3.6 Common Issues & Troubleshooting](#36-common-issues--troubleshooting)
  - [3.7 Known Limitations & Constraints](#37-known-limitations--constraints)
  - [3.8 Estimated Testing Timeline](#38-estimated-testing-timeline)
- [4. Quick Start Guide](#4-quick-start-guide)
  - [4.1 Before You Begin](#41-before-you-begin)
  - [4.2 Scenario Selection: Content Generation](#42-scenario-selection-content-generation)
  - [4.3 Configuration](#43-configuration)
  - [4.4 Running Your First Test](#44-running-your-first-test)
  - [4.5 Understanding Sample Prompts](#45-understanding-sample-prompts)
  - [4.6 Viewing Results](#46-viewing-results)
  - [4.7 Key Metrics to Look For](#47-key-metrics-to-look-for)
  - [4.8 What's Next?](#48-whats-next)
- [5. Running Model Selection Tests](#5-running-model-selection-tests)
  - [5.1 Testing Strategy Overview](#51-testing-strategy-overview)
  - [5.2 Content Generation Scenario](#52-content-generation-scenario)
  - [5.3 Conversational Chat Scenario](#53-conversational-chat-scenario)
  - [5.4 RAG / Long-Context Scenario](#54-rag--long-context-scenario)
  - [5.5 Common Configuration Parameters](#55-common-configuration-parameters)
  - [5.6 Multi-Model Comparison Workflow](#56-multi-model-comparison-workflow)
  - [5.7 Troubleshooting Model Selection Tests](#57-troubleshooting-model-selection-tests)
  - [5.8 Summary of Findings](#58-summary-of-findings)
- [6. Understanding Results](#6-understanding-results)
  - [6.1 Overview of AIPerf Output](#61-overview-of-aiperf-output)
  - [6.2 Core Metrics Explained](#62-core-metrics-explained)
  - [6.3 Reading Latency-vs-Concurrency Curves](#63-reading-latency-vs-concurrency-curves)
  - [6.4 Mapping Results to Service-Level Agreements (SLAs)](#64-mapping-results-to-service-level-agreements-slas)
  - [6.5 Presenting Model Comparisons](#65-presenting-model-comparisons)
  - [6.6 Preliminary Infrastructure Insights (Placeholder)](#66-preliminary-infrastructure-insights-placeholder)
  - [6.7 Validating Result Quality](#67-validating-result-quality)
  - [6.8 Using Results for Next Steps](#68-using-results-for-next-steps)
- [7. Troubleshooting & FAQ](#7-troubleshooting--faq)
- [8. Technical Reference](#8-technical-reference)
  - [8.1 AIPerf CLI Flags Reference](#81-aiperf-cli-flags-reference)
  - [8.2 Environment Variable Reference](#82-environment-variable-reference)
  - [8.3 JSONL Prompt Schema Reference](#83-jsonl-prompt-schema-reference)
  - [8.4 Directory Structure Reference](#84-directory-structure-reference)
  - [8.5 Kubernetes Resource Reference](#85-kubernetes-resource-reference)
  - [8.6 Metrics Calculation Reference](#86-metrics-calculation-reference)
  - [8.7 Git Workflow for Reproducibility](#87-git-workflow-for-reproducibility)

---

## 1. Executive Summary

This document provides a comprehensive guide for running reproducible LLM performance tests using NVIDIA AIPerf on Kubernetes. The testing suite is backend-agnostic and works with any OpenAI-compatible endpoint (NIM, vLLM, TGI, etc.). It enables two primary workflows: **Model Selection** (choosing the right model for your use cases) and **Infrastructure Sizing** (determining the compute resources needed to meet your SLAs).

### 1.1 Goals & Objectives

- **Model Selection**: Identify the model that best balances quality, speed, and cost for your specific use cases
- **Infrastructure Sizing**: Determine the compute resources required to meet performance standards under expected load
- **User Experience Assurance**: Validate responsiveness (TTFT, ITL, goodput) against real traffic patterns before production launch
- **Risk Mitigation**: Understand capacity limits and failure points in advance, so deployment decisions rest on data rather than estimates

### 1.2 Business Value

- **Cost Optimization**: Right-size infrastructure through precise capacity planning, avoiding over-provisioning while maintaining SLA compliance
- **Performance Guarantees**: Establish SLAs backed by empirical data, not theoretical estimates
- **Faster Time-to-Market**: Accelerate deployment decisions with clear performance data
- **Reduced Downtime Risk**: Identify bottlenecks before they impact production users
- **Budget Planning**: Forecast infrastructure costs accurately as the user base grows

### 1.3 High-Level Process Overview

**Two-Phase Testing Approach:**

- **Phase 1: Model Selection** (1-3 days per model candidate)
  - Compare 2+ models across workload profiles
  - Evaluate UX-relevant metrics (TTFT, ITL, Goodput)
  - Identify best model for your use cases

- **Phase 2: Infrastructure Sizing** (3-5 days per configuration)
  - Test selected model against concurrency ladder
  - Identify capacity limits and "knee of the curve"
  - Calculate required hardware footprint

**Resource Requirements:**
- **Compute**: Access to representative production-like hardware
- **Network**: Stable connectivity to LLM endpoints
- **Time**: 1-2 weeks for complete analysis (depending on complexity)
- **Expertise**: DevOps/SRE for Kubernetes deployment and configuration

**Deliverables:**
- **Raw Performance Data**: Complete AIPerf exports for all test scenarios
- **Analysis Reports**: Detailed metrics breakdown and interpretation
- **Model Recommendations**: Evidence-based model selection guidance
- **Performance Baselines**: Establish current performance benchmarks
- **[PLACEHOLDER: Infrastructure Blueprints]**: Detailed hardware sizing recommendations (coming soon)

---

## 2. Technical Overview

### 2.1 Architecture Overview

The testing suite consists of three main components that work together to generate reproducible performance data:

**System Components:**
- **NVIDIA AIPerf**: Industry-standard benchmarking tool that executes test scenarios and captures performance metrics
- **Kubernetes (K8s)**: Container orchestration platform that deploys and manages AIPerf jobs
- **LLM Endpoints**: Target OpenAI-compatible API services being tested (NIM, vLLM, TGI, etc.)

**Data Flow:**
1. AIPerf reads scenario configuration from bash scripts (script-as-config)
2. K8s Job spawns AIPerf container with test parameters
3. AIPerf generates synthetic/replay traffic against LLM endpoint
4. Performance metrics are captured and exported as raw CSV/JSON files
5. Results are collected for analysis and reporting

**Deployment Architecture:**
```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│   Kubernetes    │──Job──▶│   AIPerf        │──API──▶│  LLM Endpoint   │
│   Cluster       │         │   Container      │         │  (OpenAI API)   │
└─────────────────┘         └──────────────────┘         └─────────────────┘
       │                              │                            │
       │                              ▼                            │
       │                    ┌──────────────────┐                  │
       │                    │  Test Results    │                  │
       │                    │  (CSV/JSON)      │                  │
       │                    └──────────────────┘                  │
       ▼                                                           │
┌─────────────────┐                                               │
│   ConfigMaps    │                                               │
│   & Secrets     │                                               │
└─────────────────┘                                               │
                                                                  │
┌─────────────────────────────────────────────────────────────────┘
│
▼
Analysis & Reporting
```

### 2.2 Testing Methodology

**Why We Test This Way:**
Traditional single-point benchmarks fail to capture real-world performance characteristics. Our methodology simulates actual production traffic patterns to identify where systems truly succeed or fail under realistic conditions.

**Workload Profiles:**
We use distinct workload profiles rather than generic prompts to mirror your actual business operations:

- **Conversational Chat**: Multi-turn assistant interactions with human think-time (2-5s between turns)
  - *Example*: Customer service dialogue where users read responses and type follow-up questions
  - *ISL*: ~150 tokens per turn, *OSL*: 200 tokens (±50), *Turns*: 3-5

- **RAG / Long-Context Q&A**: Single-turn queries with large document context
  - *Example*: Analyzing a 4,000-token technical manual and answering specific questions
  - *ISL*: 4,000 tokens (fixed), *OSL*: 250 tokens, *Turns*: 1

- **Content Generation**: Long-form creative/marketing content from brief inputs
  - *Example*: Generating 800-token blog post from 100-token topic outline
  - *ISL*: 100 tokens (fixed), *OSL*: 800 tokens, *Turns*: 1

**Real-World Traffic Simulation:**
- **Think-time**: Realistic delays between conversation turns prevent "unrealistic robotic hammering" of APIs
  - Human-facing scenarios: 2-5 seconds (read time + typing time)
  - Agentic/tool-calling scenarios: 300-800ms (tool round-trip delay)
- **Input/Output Variation**: Each profile defines realistic ISL/OSL ranges based on actual use cases
- **Multi-turn Context**: Conversation scenarios test context window performance across multiple exchanges

### 2.3 Key Technical Concepts

**Script-as-Config Approach:**
To ensure absolute reproducibility, each scenario is defined as a single bash script containing the complete AIPerf invocation with all parameters. This eliminates configuration drift between documentation and implementation.

**Reproducibility:**
All scenario scripts and their raw output exports are committed to Git, with AIPerf version pinned per run. This ensures consistent results across different environments and over time.

**OpenAI-Compatible API Support:**
The suite works with any backend that implements the OpenAI API specification, including NVIDIA NIM, vLLM, TGI, and others. Tests are backend-agnostic and focus on performance characteristics rather than implementation details.

**Streaming vs. Non-Streaming:**
- **Streaming tests**: Measure Time to First Token (TTFT) and Inter-Token Latency (ITL) for interactive use cases
- **Non-streaming tests**: Measure total end-to-end latency for batch and non-interactive workloads

### 2.4 Technology Stack

**NVIDIA AIPerf** *(version pinned per run — the K8s Job manifests currently reference `nvcr.io/nvidia/ai-dynamo/aiperf:0.10.0`)*
Industry-standard LLM benchmarking tool that provides:
- Synthetic and replay-based workload generation
- Comprehensive performance metrics capture
- Multi-concurrency testing capabilities
- Export in standardized CSV/JSON formats

**Kubernetes**
Container orchestration platform that enables:
- Isolated test environments via Jobs
- Scalable deployment across clusters
- Secrets and configuration management
- Consistent execution across environments

**Output Formats**
- **CSV Files**: Raw performance metrics with detailed telemetry
- **JSON Files**: Structured data for programmatic analysis
- **Artifacts Directory**: All test outputs stored in timestamped directories

---

## 3. Prerequisites & Environment Setup

### 3.1 Infrastructure Requirements

**Kubernetes Cluster**
- Kubernetes v1.25+ (compatible with standard K8s Job API)
- Minimum 2 nodes with at least 4 CPUs and 8GB RAM each
- Persistent storage for test artifacts (for result retention)
- Network connectivity to LLM endpoints being tested
- Default storage class configured for persistent volumes

**LLM Endpoint Accessibility**
- OpenAI-compatible API endpoint URL and port
- API key authentication (if required)
- **Critical**: Model-API endpoints must be reachable from the testing environment
- TLS certificate verification (or disabled if using self-signed certs)

### 3.2 Software Requirements

**On Your Development Machine:**
- `kubectl` v1.25+ (cluster access and management)
- `git` (for repository operations and reproducibility)
- Bash shell or compatible terminal

**In the Kubernetes Cluster:**
- Container runtime (Docker, containerd, etc.)
- Pull access to AIPerf container images:
  - **Primary**: NVIDIA NGC catalog (if you have NVIDIA credentials)
  - **Alternative**: Private container registry (ensure pull secrets are configured)
- Network policies allowing outbound API calls to test endpoints

### 3.3 Access Requirements

**Repository Access**
- Git clone access to the testing suite repository
- Read access to scenario scripts and configuration files
- Write access if you plan to commit test results back

**Cluster Access**
- `kubectl` configured with cluster credentials
- Namespace where test jobs will run (default: `aiperf`)
- RBAC permissions: create Job, Pod, ServiceAccount, ConfigMap, Secret

**API Endpoint Access**
- API endpoint URL (e.g., `https://your-llm-endpoint.com:8000`)
- API key or authentication credentials
- Testing quota/limits (if applicable) to avoid rate limiting during tests

### 3.4 Configuration Management

**Secrets & Configuration:**
- **API Keys**: Use Kubernetes Secrets for sensitive data (API keys, authentication tokens)
  - **Note**: While we document K8s Secrets, you can integrate with any vault solution (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, etc.) using your preferred injection mechanism
- **Test Parameters**: Use ConfigMaps or environment variables for non-sensitive configuration

**Resource Allocation:**
- **Default Limits**: 2 CPUs, 2GB RAM per AIPerf job (suitable for most scenarios; see the `resources` block in each Job manifest)
- **Adjustment Guidelines**: 
  - High-concurrency tests: Increase resources proportionally
  - Large-context scenarios: May require additional memory
  - Scale based on your cluster capacity and test requirements
- **Storage**: One shared 20Gi persistent volume claim (`aiperf-model-selection-results`) across all model-selection scenarios; each scenario writes to its own subdirectory (configurable in `results-pvc.yaml`)

### 3.5 Quick Environment Verification

**Verify K8s Access:**
```bash
kubectl cluster-info
kubectl get nodes
```

**Verify Namespace:**
```bash
kubectl get namespaces
# Create default namespace if needed:
kubectl create namespace aiperf
kubectl config set-context --current --namespace=aiperf
```

**Verify Network Connectivity:**
```bash
# Test connectivity to your LLM endpoint
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v https://your-llm-endpoint.com:8000/v1/models
```

**Verify Container Pull Access:**
```bash
# Test NGC pull (requires NGC credentials)
kubectl run image-test --image=nvcr.io/nvidia/ai-dynamo/aiperf:0.10.0 --rm -it --restart=Never -- \
  echo "NGC image pull successful"

# OR test private registry pull
kubectl run image-test --image=your-registry.com/aiperf:latest --rm -it --restart=Never -- \
  echo "Private registry pull successful"
```

### 3.6 Common Issues & Troubleshooting

**Issue: Model-API Not Reachable from Testing Environment**
- **Symptoms**: Connection timeouts, DNS resolution failures
- **Solutions**: 
  - Verify network policies allow egress traffic to API endpoint
  - Check firewall rules and corporate proxy settings
  - Test connectivity from within the cluster using the verification commands above
  - Ensure API endpoint is accessible from cluster network (not just from your dev machine)

**Issue: Test Scripts or Prompts Missing**
- **Symptoms**: File not found errors, unexpected prompt behavior
- **Solutions**:
  - Verify repository clone was successful and complete
  - Check that you're in the correct branch/commit
  - Confirm scenario scripts exist in `model-selection/` directory
  - Validate prompt files in `model-selection/prompts/` directory
  - Use `git status` to ensure you have all necessary files

**Issue: Container Image Pull Failures**
- **Symptoms**: Image pull errors, authentication failures
- **Solutions**:
  - Verify NGC credentials or private registry pull secrets are configured
  - Check image tags and version compatibility
  - Ensure network allows access to container registry
  - Test image pull manually using verification commands

**Issue: Insufficient Cluster Resources**
- **Symptoms**: Pending pods, resource quota exceeded
- **Solutions**:
  - Scale up cluster resources (add nodes or increase node capacity)
  - Adjust resource limits in job specifications
  - Reduce concurrency levels to match available resources
  - Check cluster resource usage with `kubectl describe nodes`

**Issue: Persistent Volume Binding Failures**
- **Symptoms**: Pod stuck in Pending state, PVC not bound
- **Solutions**:
  - Verify storage class is available and configured
  - Check storage capacity and available storage
  - Ensure default storage class is set
  - Review PVC status with `kubectl get pvc`

### 3.7 Known Limitations & Constraints

**Current Implementation Scope:**
- 3 of 6 model-selection scenarios are implemented: content_generation, rag_long_context, and conversational_chat — note that conversational_chat currently has a known dataset-schema issue (see Section 7.4)
- Sizing suite not yet implemented
- Jumphost fallback mode (native install, no Docker) is roadmap

**Test Execution Constraints:**
- Concurrent tests should be limited to avoid overwhelming target endpoints
- Some endpoints have rate limits - adjust concurrency accordingly
- Large context scenarios may hit model context window limits

**Resource Considerations:**
- Each AIPerf job consumes cluster resources (CPU/Memory)
- Result storage grows with test duration and concurrency levels
- Network bandwidth between cluster and LLM endpoints affects measurements

### 3.8 Estimated Testing Timeline

**Model Selection Suite** (per model candidate):
- Setup and environment verification: 4-8 hours
- Test execution across 3 scenarios: 1-3 days
- Results analysis and reporting: 4-8 hours
- **Note**: Timeline depends on customer-specific requirements, cluster resources, endpoint performance, and desired thoroughness

**Capacity/Sizing Suite** (per configuration):
- Setup and environment verification: 4-8 hours
- Test execution across concurrency ladder: 3-5 days
- Results analysis and reporting: 4-8 hours
- **Note**: Timeline depends on customer-specific requirements, cluster resources, endpoint performance, and desired thoroughness

---

## 4. Quick Start Guide

### 4.1 Before You Begin

**Prerequisites Checklist:**
- ✅ Completed Section 3: Prerequisites & Environment Setup
- ✅ Kubernetes cluster accessible with `kubectl`
- ✅ Network connectivity to your LLM endpoint confirmed
- ✅ Container image pull access verified (NGC or private registry)
- ✅ Default namespace `aiperf` created

**What You'll Accomplish:**
- Configure and run a simplified content generation test
- Access and understand test results
- See the testing workflow end-to-end

**Estimated Time:** 30-60 minutes for the complete quick start

### 4.2 Scenario Selection: Content Generation

We'll use the `content_generation` scenario for your quick start because it:
- Demonstrates all key metrics (TTFT, ITL, goodput)
- Is single-turn (simpler to understand)
- Has clear business relevance (generating marketing content, articles, etc.)
- Runs quickly compared to multi-turn scenarios

**Note**: This quick start uses default parameters. Later, you'll customize with specific features for your actual content generation testing (custom prompts, output length requirements, etc.).

### 4.3 Configuration

#### Step 1: Configure the Job Manifest

The test's target model and endpoint are set as environment variables in the Job manifest, `model-selection/k8s/content-generation-job.yaml`. Before applying it, edit:

- `MODEL` — your model's identifier (as expected by the endpoint)
- `URL` — your LLM endpoint's base URL (must be reachable from the cluster)
- `image:` — pin to the exact NGC AIPerf tag you're using
- `TOKENIZER_PATH` — HuggingFace repo ID or local path for the tokenizer

If your tokenizer is a gated/private HuggingFace repo (e.g., `meta-llama/*`), also create the optional HF token secret:

```bash
kubectl create secret generic aiperf-hf-token \
  --from-literal=HF_TOKEN='hf_your_token_here' -n aiperf
```

**Success Indicator**: The manifest's `MODEL` and `URL` values point at your endpoint, and (if needed) `kubectl get secret aiperf-hf-token -n aiperf` lists the secret.

#### Step 2: Verify Test Scripts

Ensure the content generation scenario files exist in your clone:

```bash
# Verify content generation script exists
ls model-selection/scripts/run_content_generation.sh

# Verify prompts exist
ls model-selection/prompts/content_generation.jsonl
```

**Success Indicator**: You should see `run_content_generation.sh` and `content_generation.jsonl` in the listings.

### 4.4 Running Your First Test

#### Step 1: Execute the Quick Start Job

The easiest path is the orchestration script, which creates the namespace, ConfigMaps, results PVC, and Job in one step (it uses the `oc` CLI by default; set `OC_BIN=kubectl` on plain Kubernetes):

```bash
./model-selection/k8s/run-test.sh -n aiperf -t content-generation
```

Or run the steps manually:

```bash
# One-time: shared results volume
kubectl apply -f model-selection/k8s/results-pvc.yaml -n aiperf

# Mount the scenario script and prompts as ConfigMaps
kubectl create configmap aiperf-content-generation-script \
  --from-file=run_content_generation.sh=model-selection/scripts/run_content_generation.sh -n aiperf
kubectl create configmap aiperf-content-generation-prompts \
  --from-file=content_generation.jsonl=model-selection/prompts/content_generation.jsonl -n aiperf

# Launch the Job
kubectl apply -f model-selection/k8s/content-generation-job.yaml -n aiperf

# Monitor job startup
kubectl get pods -l job-name=aiperf-content-generation -n aiperf
```

**Success Indicator**: You should see a pod with status `Running` or `Completed` after 30-60 seconds.

#### Step 2: Monitor Test Progress

Watch the job execution:

```bash
# View job status
kubectl get job aiperf-content-generation -n aiperf

# View pod logs to see test progress
kubectl logs -f job/aiperf-content-generation -n aiperf
```

**What to Expect in Logs:**
- AIPerf initialization messages
- Test configuration summary
- Progress indicators (requests completed, metrics collected)
- Final results summary

**Success Indicator**: Job status should show `COMPLETED` and logs should show "Test completed successfully" after 5-15 minutes (depending on your endpoint performance).

### 4.5 Understanding Sample Prompts

The content generation scenario uses realistic prompts that mirror business use cases. Here are 5 sample prompts you'll find in `model-selection/prompts/content_generation.jsonl`:

```
{"text_input": "Write a blog post introduction (3-4 sentences) announcing our company's new AI-powered customer support chatbot, aimed at small business owners who are skeptical of automation replacing human support."}

{"text_input": "Draft a product description for a stainless steel insulated water bottle, 32oz, keeps drinks cold for 24 hours. Target audience: outdoor enthusiasts and hikers. Tone: energetic and adventurous."}

{"text_input": "Write a LinkedIn post (under 200 words) from a VP of Engineering announcing that their team just shipped a major platform migration with zero downtime, thanking the team."}

{"text_input": "Compose a marketing email subject line and body promoting a 20%-off end-of-season sale for a home goods e-commerce store. Keep the tone warm and low-pressure."}

{"text_input": "Write a short press release opening paragraph announcing a Series B funding round of $40 million for a climate-tech startup building carbon capture hardware."}
```

**Note**: These prompts test the model's ability to generate high-quality, business-relevant content from brief inputs. Your actual tests may use custom prompts specific to your use cases.

### 4.6 Viewing Results

#### Step 1: Access Test Results

Results are written to `/artifacts/content-generation` on the shared results volume:

```bash
# Find the completed pod
POD_NAME=$(kubectl get pods -l job-name=aiperf-content-generation -n aiperf -o jsonpath='{.items[0].metadata.name}')

# Copy results from the pod
kubectl cp aiperf/$POD_NAME:/artifacts/content-generation ./quick-start-results --container=aiperf

# List downloaded results
ls quick-start-results/
```

**Success Indicator**: You should see the AIPerf export (CSV and JSON files) in the `./quick-start-results/` directory.

**Note**: `kubectl cp` requires the pod to still exist. If it has been cleaned up, mount the `aiperf-model-selection-results` PVC in a temporary pod to retrieve the files.

#### Step 2: Understand Result Structure

The output is the raw AIPerf export — this suite deliberately adds no processed report layer on top of it:
- **CSV export**: Detailed per-request metrics (TTFT, ITL, latencies, token counts)
- **JSON export**: Aggregated metrics plus the full test configuration, for programmatic analysis and reproducibility

**Key Files to Examine:**
```bash
# View the aggregated JSON export
cat quick-start-results/*.json

# View a sample of the detailed per-request metrics
head -n 20 quick-start-results/*.csv
```

### 4.7 Key Metrics to Look For

In your results, focus on these critical metrics (actual values will appear after your test runs):

**Time to First Token (TTFT)**
- What it measures: Time from request to first token generation
- Why it matters: User-perceived responsiveness
- Good range: < 1 second for interactive use cases

**Inter-Token Latency (ITL)**  
- What it measures: Average time between consecutive tokens
- Why it matters: Streaming quality and user experience
- Good range: < 100ms for smooth streaming

**Goodput**
- What it measures: Effective tokens per second considering all latencies
- Why it matters: Overall system efficiency
- Good range: Varies by model and hardware, higher is better

**Request Completion Rate**
- What it measures: Percentage of successful requests
- Why it matters: System reliability
- Good range: > 99% for production systems

### 4.8 What's Next?

**If your first test was successful:**
- Customize parameters for your specific content generation needs
- Run additional scenarios (conversational_chat, rag_long_context)
- Increase concurrency levels to test system capacity
- Implement your results retrieval and reporting process

**If you encountered issues:**
- Check troubleshooting section (Section 3.6)
- Verify network connectivity and API credentials
- Review job and pod logs for error messages
- Ensure cluster resources are sufficient

**Next Steps in Documentation:**
- Section 5: Running Model Selection Tests (detailed scenario configuration)
- Section 6: Understanding Results (detailed metrics interpretation)
- Section 7: Troubleshooting & FAQ

---

## 5. Running Model Selection Tests

This section provides a comprehensive, customer-focused guide for running reproducible model selection tests using the NVIDIA AIPerf suite on Kubernetes. It is organized around three core scenarios that reflect common business use cases:

- **Content Generation** – Long-form marketing/content creation  
- **Conversational Chat** – Multi-turn customer service interactions  
- **RAG / Long-Context** – Business intelligence and document analysis  

### 5.1 Testing Strategy Overview
- **Baseline Approach**: Test each model candidate across workload profiles at multiple concurrency levels  
- **Concurrency Flexibility**: Default suggestion uses 1/5/10/25 ladder, but you may adjust based on:
  - Expected production load patterns  
  - Available cluster resources  
  - Specific SLA requirements  
- **Test Duration Factors**:  
  - Base request processing time (varies by model/endpoint)  
  - Number of requests per scenario  
  - Concurrency level (higher concurrency = more throughput but longer queueing)  
  - Think-time delays (conversational scenarios with multi-turn)  
  - Warm-up/cool-down periods  
  - Typical range: 20-60 minutes per scenario per concurrency level  

When comparing multiple model candidates, follow the round-robin workflow described in [Section 5.6](#56-multi-model-comparison-workflow).

### 5.2 Content Generation Scenario  
**Business Use Cases**:  
- Marketing copy generation  
- Article/report writing  
- Creative content production  
- Product description text generation  

**Technical Configuration**:  
- Fixed input (~100 tokens): Short creative/marketing briefs from real prompts  
- Fixed output (800 tokens): Long-form content generation  
- Single-turn interaction (no conversation/think-time flags)  
- Streaming enabled for token-by-token output  
- Dataset: `content_generation.jsonl` with real marketing prompts  

**Execution**:  
```bash
# Set environment variables (or use defaults)
export MODEL=my-llm-instruct
export URL=http://localhost:8000
export ENDPOINT_TYPE=chat
export ENDPOINT_PATH=/v1/chat/completions

# Run with desired concurrency (e.g., 5)
CONCURRENCY=5 ./run_content_generation.sh
```

**Duration Expectation**: 20-40 minutes per concurrency level (depends on endpoint speed)

**Results Interpretation (Qualitative Framework)**:  
- **TTFT**: "Lower is better for perceived responsiveness" - impacts how quickly content starts appearing  
- **ITL**: "Lower improves streaming quality" - smoother reading experience  
- **Goodput**: "Higher indicates better throughput efficiency" - balances speed and error rate  
- **Request Completion Rate**: "Higher indicates better reliability" - % of successful generations  

### 5.3 Conversational Chat Scenario  

> **⚠ Known issue**: This scenario's `multi_turn` dataset is currently rejected by AIPerf with a Pydantic validation error — see [Section 7.4](#74-known-issues--limitations) for status and workarounds. The configuration below describes the intended workload; use the other two scenarios until the schema issue is resolved.

**Business Use Cases**:  
- Customer service chatbots  
- Virtual assistants  
- Interactive tutoring systems  
- Therapeutic or support agents  

**Technical Configuration**:  
- Multi-turn conversations with realistic think-time simulation  
- Input: Conversation history (~150 tokens/turn)  
- Output: Responses (~200 tokens/turn)  
- Turn delay simulation (~3.5s ± 0.75s) mimicking human typing time  
- Dataset: `conversational_chat.jsonl` with real dialogue samples  

**Execution**:  
```bash
# Same environment setup as content generation
# Additional parameter for turn delays:
--conversation-turn-delay-mean 3500 \
--conversation-turn-delay-stddev 750
```

**Duration Expectation**: 25-50 minutes per concurrency level (longer due to turn delays)

**Results Interpretation**:  
- TTFT: "Lower improves perceived responsiveness of first reply"  
- ITL: "Lower improves streaming conversation flow"  
- Turn Completion Latency: "End-to-end exchange time matters"  
- Conversation Success Rate: Measures multi-turn interaction stability  
- Context Handling: Qualitative assessment of coherent follow-ups  

### 5.4 RAG / Long-Context Scenario  
**Business Use Cases**:  
- Document analysis for research/legal/financial teams  
- Technical support knowledge base retrieval  
- Customer support ticket classification  
- Large-context summarization tasks  

**Technical Configuration**:  
- Large fixed input (4,000 tokens): SOURCE DOCUMENTS or context passages  
- Moderate output (250 tokens): Answers/summaries/extractions  
- Single-turn interaction (or multi-turn with context window limits)  
- Streaming enabled for generating multiple tokens from long context  
- Dataset: `rag_long_context.jsonl` with real document samples  

**Execution**:  
```bash
# Similar setup to content generation, but with a different script/manifest
kubectl apply -f model-selection/k8s/rag-long-context-job.yaml -n aiperf
```

**Duration Expectation**: 30-60 minutes per concurrency level (often longest due to context processing complexity)

**Results Interpretation**:  
TTFT: "Lower indicates faster initial context processing"  
ITL: "Lower improves answer delivery smoothness"  
Context Utilization Effectiveness: "Higher suggests better use of provided information" (qualitative)  
Request Completion Rate: "Higher indicates reliable complex query handling"  
- Qualitative note: Evaluate whether responses actually use relevant context points  

### 5.5 Common Configuration Parameters  
**Required Parameters** (must be set for all tests):  
- `MODEL`: Target model identifier/name  
- `URL`: LLM endpoint base URL (e.g., `http://localhost:8000`)  
- `ENDPOINT_TYPE`: `chat` for OpenAI-compatible chat completions APIs (the default)  
- `ENDPOINT_PATH`: Typically `/v1/chat/completions`  

**Optional Parameters** (safe defaults):  
- `CONCURRENCY`: Default `1`, set to `5/10/25` for load testing  
- `TOKENIZER_PATH`: For local tokenizers (defaults to HF auto-resolution)  
- `HF_TOKEN`: For private/gated model tokenizers  
- `OUTPUT_DIR`: Default `./artifacts` (change to store elsewhere)  

**Configuration Methods**:  
- **Recommended**: Environment variables (no script changes needed)  
- **Alternative**: Direct script modification for permanent baseline changes  
- **Best Practice**: Create wrapper scripts for specific test suites  

### 5.6 Multi-Model Comparison Workflow  
**Primary Use Case**: Selecting the optimal model from candidates based on performance.

Our recommended default methodology is **round-robin by concurrency level** — test every candidate at one load level before moving to the next. Direct comparison at each load level makes relative scaling characteristics easy to see, and keeps environmental drift (cluster state, time of day, network conditions) from favoring one model.

**Recommended Process**:  
1. Define model candidates (2-4 models for meaningful comparison)  
2. Prepare identical test environment (same cluster, time of day, network conditions)  
3. For each concurrency level [1, 5, 10, 25]:  
   a. Test Model A at current concurrency  
   b. Test Model B at current concurrency  
   c. Test Model C at current concurrency (if applicable)  
   d. [Optional] Re-test reference model to check for drift  
4. Collect and normalize results for comparison  
- **Comparison Framework**:  
  - Create tables showing metrics side-by-side across models/concurrency levels  
  - Use radar/spider charts for multi-metric comparison  
  - Apply weighting based on business priorities (latency vs. throughput vs. quality)  
  - Identify Pareto-optimal models (no worse on any metric, better on at least one)  
- **Decision Guidance**:  
  - Latency-sensitive apps: Prioritize low TTFT/ITL  
  - Throughput-focused apps: Prioritize high goodput/request rate  
  - Quality-sensitive apps: May accept higher latency for better output fidelity  
  - Document rationale for selection to support future re-evaluation  
- **Customization**: For specific use cases, you may focus on particular scenarios only  

### 5.7 Troubleshooting Model Selection Tests  
**Scenario-Specific Issues**:  
- Content Generation: Output truncation → Check `OUTPUT_TOKENS_MEAN` setting  
- Conversational Chat: Context drift in prolonged dialogues → May indicate context window limits  
- RAG: Irrelevant answers → May indicate retrieval or context window issues  
- Configuration Issues:  
  - Connection errors → Verify endpoint URL, network access, firewall rules  
  - Authentication failures → Check API key/token validity and format  
  - Dataset not found → Verify `INPUT_FILE` path or correct branch  
  - Tokenizer errors → Validate `TOKENIZER_PATH` or use HF auto-resolution  
- Resource Constraints:  
  - GPU memory exhaustion → Check actual vs. reported model size  
  - Rate limiting → Reduce concurrency or add delays between batches  
- Validation Steps:  
  - Confirm input/output token counts match expectations  
  - Spot-check responses for basic coherence (not quality assessment)  
  - Verify no unexpected errors in job logs  
  - Check warm-up vs. actual request counts in logs  

### 5.8 Summary of Findings  
- The testing framework enables data-driven model selection through standardized, reproducible evaluations  
- Business value comes from quantifying performance across UX-relevant metrics rather than subjective impressions  
- Results should inform both model choice and infrastructure requirements for production deployment  
- All three implemented scenarios contribute distinct insights: content generation for output quality, chat for multi-turn fluency, RAG for context handling  
- **Note**: This section focuses on operational testing; output quality validation requires separate human evaluation filters

---

## 6. Understanding Results

### 6.1 Overview of AIPerf Output

Each test run writes its raw AIPerf export - CSV and JSON files - into the scenario's output directory (`OUTPUT_DIR`, default `./artifacts/<scenario>/` locally, `/artifacts/<scenario>/` on the shared PVC in Kubernetes). This raw export is the deliverable: the suite deliberately adds no processed or reformatted report layer on top of it, so results stay directly traceable to the tool that produced them.

- The **CSV export** contains detailed per-request telemetry (TTFT, ITL, latencies, token counts).
- The **JSON export** contains aggregated metrics plus the complete test configuration, for programmatic analysis and reproducibility.

For a quick-reference summary of which metrics each scenario emphasizes, see the metric tables in `docs/metrics/model-selection.md`.

### 6.2 Core Metrics Explained

The metric definitions and calculations are documented in [Section 8.6](#86-metrics-calculation-reference); the four to focus on for model selection are TTFT (perceived responsiveness), ITL (streaming smoothness), goodput (percentage of requests meeting all latency targets simultaneously), and success rate (reliability).

**[PLACEHOLDER: chart illustrating typical TTFT and ITL versus concurrency for a well-performing model vs. a poorly-scaling model - to be added after the first customer test runs]**

### 6.3 Reading Latency-vs-Concurrency Curves

Plot a latency metric (e.g., P95 TTFT) against concurrency level. The curve typically shows three zones:

- **Linear zone**: Latency stays roughly flat as concurrency grows - the system is comfortably under-utilized.
- **The knee**: The point where latency begins to rise sharply. This is the maximum sustainable capacity.
- **Saturation zone**: Latency spikes dramatically; users experience significant delays and requests may start failing.

A simple heuristic for locating the knee: step through the concurrency ladder and watch the latency increase per added concurrency step - the knee is where that increase jumps well beyond the trend of the previous steps (e.g., latency growth per step more than doubles).

### 6.4 Mapping Results to Service-Level Agreements (SLAs)

Use your SLA to read the maximum sustainable concurrency directly off the curve. For example, if your requirement is "95% of requests must show a first token in under 2 seconds," find the highest concurrency level at which P95 TTFT is still below 2s - that is your capacity limit for the tested configuration.

**[PLACEHOLDER: example table showing concurrency, P95 TTFT, and SLA compliance status - to be filled with real run data]**

### 6.5 Presenting Model Comparisons

Follow the round-robin workflow in [Section 5.6](#56-multi-model-comparison-workflow), then present results as side-by-side tables of TTFT, ITL, goodput, and success rate - one table per scenario, one row per model, one column group per concurrency level. Prioritize metrics by business focus: latency-sensitive applications weight TTFT/ITL, throughput-sensitive applications weight goodput and request rate.

**[PLACEHOLDER: side-by-side comparison table - to be filled with real run data]**

### 6.6 Preliminary Infrastructure Insights (Placeholder)

The knee observed in model-selection curves provides a rough upper bound for what a single deployment of the tested configuration can sustain. Full infrastructure sizing - the dedicated concurrency ladder up to 200 concurrent users - will be covered by the Capacity/Sizing suite in a future version of this guide.

### 6.7 Validating Result Quality

Before drawing conclusions from a run, verify the results look reasonable:

- Check that input/output token counts match the scenario's configured ISL/OSL.
- Confirm the success rate - if more than a few percent of requests failed, latency numbers describe only the surviving requests and may be misleadingly good.
- Spot-check a few responses for basic coherence (this is a sanity check, not a quality assessment).
- Scan the job logs for errors and confirm the warm-up request count matches the configuration.

### 6.8 Using Results for Next Steps

Once you've selected a model:

1. Commit the raw results to the repository (see [Section 8.7](#87-git-workflow-for-reproducibility)).
2. Document the model-selection rationale alongside the data, so the decision can be re-evaluated later.
3. Carry the chosen model forward into the infrastructure-sizing phase, using the observed knee as the starting hypothesis for capacity.

---

## 7. Troubleshooting & FAQ

This section covers common issues encountered when running the model selection test suite, organized by where in the workflow the problem appears. For basic environment setup issues (API connectivity, missing scripts, image pulls, PVC binding) see [Section 3.6](#36-common-issues--troubleshooting). For scenario-specific configuration problems see [Section 5.7](#57-troubleshooting-model-selection-tests).

### 7.1 Setup & Environment

**Q: My pod is stuck in "Pending" — what do I check?**

A: A pending pod almost always means insufficient cluster resources or a missing PVC. Run:
```bash
kubectl describe pod <pod-name>
kubectl get pvc
kubectl describe nodes
```
Common causes: PVC not bound (check storage class name matches your cluster), node CPU/memory exhaustion (reduce resource requests or add nodes), or a taint that tolerates no pods. See [Section 3.6](#36-common-issues--troubleshooting) for PVC troubleshooting.

**Q: The pod starts but immediately crashes with "Permission denied" on cache directories.**

A: The AIPerf container image's default `HF_HOME` (e.g., `/app/.cache/huggingface`) is not writable by non-root users. Set `HF_HOME` to a writable path:
```bash
export HF_HOME=/tmp/hf-cache
```
The scenario scripts support this via the `HF_HOME` environment variable. The script will create the directory if it doesn't exist.

**Q: I get "ImagePullBackOff" or "ErrImagePull" on the AIPerf container image.**

A: This means the cluster cannot pull the image from NGC or your private registry. Check:
- The image tag in the Job YAML matches a real published tag (see `nvcr.io/nvidia/ai-dynamo/aiperf:0.10.0` — you may need to update this).
- Your cluster has pull credentials for NGC (`nvcr.io`) or your private registry.
- Your cluster has network egress to the container registry (corporate proxies/firewalls can block this).

**Q: I can't reach my LLM endpoint from the cluster — connection timeouts.**

A: Follow the connectivity verification steps in [Section 3.5](#35-quick-environment-verification). The most common causes are:
- Network policies blocking egress to the endpoint's IP/port.
- The endpoint listening on `localhost` only (must be reachable from outside the host).
- TLS certificate issues with self-signed certs (test with `curl -k` first).
- DNS resolution failure inside the cluster (test with `kubectl run dns-test --image=busybox -- nslookup your-endpoint-host`).

### 7.2 Test Execution

**Q: The test runs but produces empty output or zero valid requests.**

A: Check the pod logs with `kubectl logs <pod-name>`. Likely causes:
- The endpoint returned all errors (check `HTTP 4xx/5xx` in logs — verify API key, endpoint URL, model name).
- No requests were sent because the input file wasn't found (the script exits early if the file is missing, but a K8s ConfigMap mount path may differ — verify paths with `kubectl exec <pod> -- ls -la /path/to/prompts/`).
- The `--streaming` flag is set but the endpoint doesn't support streaming (switch to non-streaming or use a compatible endpoint).

**Q: AIPerf fails with "Failed to load tokenizer" and suggests --tokenizer-trust-remote-code.**

A: Some HuggingFace repos (custom fine-tunes, quantized models, GGUF conversions) use a non-standard `tokenizer_config.json` that requires executing Python code from the repo. Set:
```bash
export TOKENIZER_TRUST_REMOTE_CODE=1
```
**Security note**: this executes arbitrary code from the HF repo — review the tokenizer implementation on HuggingFace before enabling.

**Q: I get a tokenizer error about a gated/private model (e.g., meta-llama/Llama-*).**

A: Gated model repos require a HuggingFace token with granted access. Either:
- Set `HF_TOKEN=hf_your_token` in the environment (the script will detect it), or
- Let the script prompt you for the token interactively.
For local tokenizer directories, the script sets `HF_HUB_OFFLINE=1` so no token is needed.

**Q: The conversational chat scenario fails with a Pydantic validation error about "turn_delay" or "extra_forbidden".**

A: This is a known, unresolved issue. The `multi_turn` dataset schema used by `run_conversational_chat.sh` differs from what the installed AIPerf version expects — AIPerf's Pydantic model rejects fields it doesn't recognize. The exact schema has not been confirmed. See [docs/scenarios/model-selection.md](../scenarios/model-selection.md) for details and current status. The `content_generation` and `rag_long_context` scenarios (which use `mooncake_trace`) do not have this issue.

**Q: AIPerf rejects my dataset with "At least one modality must be provided" or expects a 'text' key.**

A: You're using `--custom-dataset-type random_pool` with a dataset keyed on `text_input`. The `random_pool` schema requires a `text` key (or `texts`, `image`, etc.). This was resolved by switching to `mooncake_trace`, which uses `text_input` and is the correct choice for deterministic single-turn replay. Update your invocation to:
```
--custom-dataset-type mooncake_trace
```
and ensure your JSONL records use the `text_input` key. See `run_rag_long_context.sh` for the confirmed-working pattern.

**Q: The test seems to hang or takes much longer than the estimated duration.**

A: Several factors can extend test time:
- **Slow endpoint**: if the underlying LLM is heavily loaded, each request takes longer → reduce concurrency or increase timeout.
- **Large output sequences**: `--output-tokens-mean 800` on a slow endpoint can take minutes per request.
- **Think-time accumulation**: conversational scenarios with 3-5 turns at 2-5s delay per turn add 6-25s per conversation before network time.
- **Rate limiting**: the endpoint may be throttling requests, causing AIPerf to back off and retry. Lower concurrency or add delays.
- Check `kubectl logs` for progress messages — AIPerf prints periodic status.

**Q: I see "429 Too Many Requests" or rate-limiting errors in the logs.**

A: Your LLM endpoint is throttling the test traffic. Mitigations:
- Reduce concurrency (`CONCURRENCY=1` to start).
- Increase `--warmup-request-count` to let the endpoint adjust.
- Add delays between requests (not currently supported by these scripts — as a workaround, reduce concurrency).
- Check your API plan/quotas with the endpoint provider.

### 7.3 Results & Metrics

**Q: My TTFT numbers are very high — is the endpoint slow or is something wrong?**

A: High TTFT can indicate:
- Endpoint prefill/processing overhead (expected for large ISL — 4k+ tokens will have higher TTFT).
- Request queueing at high concurrency (check TTFT variance across requests).
- Network latency between cluster and endpoint (run from same region/cloud if possible).
- Cold start / model loading (first request after idle period is slower — AIPerf's warmup requests mitigate this).
Compare your values against the endpoint's advertised performance or run a quick single-request baseline with `curl` to isolate network + endpoint latency.

**Q: Goodput is 0% — what does that mean?**

A: Goodput measures the percentage of requests that meet *all* latency targets (TTFT, ITL, total latency) simultaneously. 0% means no request met every target. This is common when:
- TTFT or ITL targets are set too aggressively (the default targets in AIPerf may be tuned for fast endpoints).
- Concurrency is too high for your endpoint (latency spikes push requests past the targets).
- The endpoint has high variance — some fast requests, many slow ones.
Check which specific latency target is being missed by examining the per-request metrics in the CSV output.

**Q: Output token counts in the results don't match my --output-tokens-mean setting.**

A: `--output-tokens-mean` is a *target* — the model generates until it decides to stop (an EOS token or reaching the model's max-tokens limit). Actual output lengths will vary around the mean. The standard deviation (`--output-tokens-stddev`, default varies by scenario) controls how tightly AIPerf enforces the target via truncation/padding. If counts are wildly different (e.g., 50 vs 800), verify the endpoint respects the `max_tokens` parameter in the chat completion request.

**Q: Why do results vary between two runs of the same test?**

A: Some variance is normal — LLM serving systems are not perfectly deterministic. Common sources of variation:
- **GPU sharing**: if other workloads use the same GPU, performance changes.
- **Network conditions**: cross-region calls see higher variance than same-region.
- **Endpoint load**: public endpoints have background traffic you can't control.
- **KV cache state**: after warmup, cache-hit rates may differ.
To minimize variance: run tests at the same time of day, on an idle cluster, and always include warmup requests. For critical comparisons, run each configuration 2-3 times and report median or P95 values.

**Q: Some requests in the output have HTTP error statuses — are they counted in the metrics?**

A: Yes and no. AIPerf typically records all attempts, including failures, in the raw CSV output. Failed requests are excluded from latency percentiles (TTFT, ITL) but the error count is reported separately. Always check the error rate / success rate metric before interpreting latency numbers — if >5% of requests failed, the latency metrics only describe the surviving requests, which may be misleadingly good. See [Section 6.7](#67-validating-result-quality) for validation guidance.

### 7.4 Known Issues & Limitations

| Issue | Status | Workaround |
|-------|--------|------------|
| **Conversational Chat multi_turn schema** — AIPerf rejects `turn_delay` field in multi-turn JSONL with a Pydantic validation error. | Unresolved. The exact `multi_turn` schema for the installed AIPerf version has not been confirmed. | Use `content_generation` or `rag_long_context` (which use `mooncake_trace`) until resolved. See [docs/scenarios/model-selection.md](../scenarios/model-selection.md) for status updates. |
| **RandomPool dataset rejection** — `--custom-dataset-type random_pool` fails with "At least one modality must be provided" when using `text_input` keys. | Resolved — switch to `mooncake_trace`. | Use `--custom-dataset-type mooncake_trace` and key your JSONL on `text_input`. All single-turn scenarios use this confirmed-working pattern. |
| **Tokenizer trust_remote_code** — some HF repos (quantized/custom tokenizers) require executing arbitrary tokenizer code. | By design, requires opt-in. | Set `TOKENIZER_TRUST_REMOTE_CODE=1` after reviewing the repo's tokenizer code. |
| **HF_HOME permission error** — default cache dir in the NGC container image is not writable by non-root users. | Workaround documented. | Set `HF_HOME=/tmp/hf-cache` (or any writable path) in the environment. |
| **Gated model tokenizers** — private HF repos (e.g., meta-llama/*) require authentication. | By design. | Set `HF_TOKEN` environment variable or let the script prompt for it. |
| **Missing scenarios** — only 3 of 6 V1 model selection scenarios are implemented. Summarization, Agentic/Tool-Calling, and Batch/Non-Interactive are not yet built. | Planned for future release. | Not applicable — no workaround available. |
| **Sizing suite** — the capacity/infrastructure sizing suite is not yet implemented. | Planned for future release. | The concurrency ladder in the model-selection suite provides a rough upper bound; see [Section 6.6](#66-preliminary-infrastructure-insights-placeholder). |

### 7.5 General FAQ

**Q: Can I add a new scenario?**

A: Yes — each scenario is a single bash script containing an `aiperf profile` invocation. To add a new one:
1. Create a new script in `model-selection/scripts/` (copy an existing one as a template).
2. Create a corresponding prompt file in `model-selection/prompts/`.
3. Create a K8s Job manifest in `model-selection/k8s/`.
4. Register it in `model-selection/k8s/run-test.sh` in the `ALL_TESTS` array.
5. Regenerate ConfigMaps with `generate-configmaps.sh`.
See the existing scenarios for reference patterns.

**Q: Can I run these tests outside Kubernetes (e.g., from my laptop or a VM)?**

A: The scripts themselves are plain bash and can run anywhere with the `aiperf` binary installed (the scripts' only external dependency). Running natively (no Docker/K8s) is planned as the "jumphost fallback" mode but is not yet implemented. Currently, the K8s delivery path is the primary and tested method.

**Q: What if my endpoint is OpenAI / Azure OpenAI / Together AI / Anthropic / etc.?**

A: As long as your endpoint exposes an OpenAI-compatible chat completions API (`/v1/chat/completions`), it will work. Set:
- `ENDPOINT_TYPE=chat`
- `ENDPOINT_PATH=/v1/chat/completions`
- `URL` to your endpoint's base URL
- `MODEL` to the deployment/model name
Some providers may require additional headers (e.g., `api-key` vs `Authorization: Bearer`) — AIPerf maps standard OpenAI auth automatically via `--api-key` or the `API_KEY` environment variable.

**Q: Can I run multiple scenarios or concurrency levels simultaneously?**

A: Not recommended — concurrent test jobs compete for endpoint capacity and cluster resources, producing confounded results. Run scenarios and concurrency levels sequentially. The `run-test.sh` script submits jobs that run in parallel on the cluster but serialize their requests to the endpoint — check your endpoint's behavior under concurrent load before relying on this.

**Q: How do I share my results with the consulting team?**

A: Commit the raw AIPerf export (CSV/JSON files) to the repository in the appropriate scenario directory under `model-selection/` or `sizing/` (once created). Tag the commit with the date and configuration tested. The repository is the single source of truth for reproducibility. See [Section 2.3](#23-key-technical-concepts) for the reproducibility commitment.

**Q: Where should I commit test results?**

A: Create a directory structure under the relevant suite — for example, `model-selection/results/<model-name>/<scenario>/<concurrency>/`. Each run's full AIPerf export directory should be committed along with a note of the AIPerf version used. This ensures the results are reproducible and traceable back to specific code and configuration.

**Q: What's the fastest way to validate a configuration is working before running a full sweep?**

A: Run at `CONCURRENCY=1` with `WARMUP_REQUESTS=0` (or the default 10). A single successful completion at baseline concurrency confirms the pipeline works. Then increase concurrency and warmup for the real test.

---

## 8. Technical Reference

### 8.1 AIPerf CLI Flags Reference

All flags used across the three implemented scenarios. Flags marked with `†` are shared across all scenarios; scenario-specific flags are noted.

| Flag | Type | Used In | Description |
|------|------|---------|-------------|
| `--model` † | string | All | Model identifier passed to the endpoint in the chat completion request body |
| `--url` † | string | All | Base URL of the OpenAI-compatible LLM endpoint |
| `--endpoint-type` † | string | All | API protocol — always `chat` for OpenAI-compatible endpoints |
| `--endpoint` † | string | All | API path — typically `/v1/chat/completions` |
| `--streaming` † | flag | All | Enable token-by-token streaming response (required for TTFT/ITL measurement) |
| `--input-file` † | string | All | Path to the JSONL prompt file |
| `--custom-dataset-type` † | string | All | Dataset schema: `mooncake_trace` (single-turn, keyed on `text_input`) or `multi_turn` (conversational) |
| `--output-tokens-mean` † | int | All | Target mean output tokens per request |
| `--concurrency` † | int | All | Number of concurrent simulated users (1 for baseline, sweep 5/10/25) |
| `--warmup-request-count` | int | All | Number of non-measured requests to warm up the endpoint before recording metrics |
| `--random-seed` | int | All | PRNG seed for reproducibility of stochastic test elements |
| `--artifact-dir` † | string | All | Output directory for CSV/JSON result files |
| `--tokenizer` | string | All | Tokenizer: local directory path or HuggingFace repo ID (optional — defaults to model name) |
| `--tokenizer-trust-remote-code` | flag | All | Allow executing tokenizer code from the HF repo (opt-in, see [Section 7.2](#72-test-execution)) |
| `--output-tokens-stddev` | int | Conversational Chat | Standard deviation for output token length (200±50) |
| `--conversation-turn-delay-mean` | int (ms) | Conversational Chat | Mean delay between conversation turns (3500ms = 3.5s human think-time) |
| `--conversation-turn-delay-stddev` | int (ms) | Conversational Chat | Stddev for turn delay (750ms, targeting 2-5s window) |

For the full AIPerf CLI reference (all available flags), run `aiperf profile --help` or consult the [NVIDIA AIPerf documentation](https://docs.nvidia.com/aiperf/).

### 8.2 Environment Variable Reference

All environment variables recognized by the scenario scripts. These can be set before invocation or provided interactively (the script falls back to prompting if not set).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MODEL` | ✓ | — | Target model identifier/name |
| `URL` | ✓ | — | LLM endpoint base URL |
| `ENDPOINT_TYPE` | | `chat` | API protocol |
| `ENDPOINT_PATH` | | `/v1/chat/completions` | API path |
| `CONCURRENCY` | | `1` | Concurrent simulated users |
| `INPUT_FILE` | | `<script-dir>/prompts/<scenario>.jsonl` | Path to prompt JSONL file |
| `CUSTOM_DATASET_TYPE` | | `mooncake_trace` or `multi_turn` | JSONL schema type |
| `OUTPUT_TOKENS_MEAN` | | per-scenario (800/200/250) | Target mean output tokens |
| `OUTPUT_TOKENS_STDDEV` | | varies | Output token stddev (conversational chat only) |
| `CONVERSATION_TURN_DELAY_MEAN_MS` | | `3500` | Turn delay mean in ms (conversational chat only) |
| `CONVERSATION_TURN_DELAY_STDDEV_MS` | | `750` | Turn delay stddev in ms (conversational chat only) |
| `WARMUP_REQUESTS` | | `10` | Warmup request count |
| `RANDOM_SEED` | | `42` | PRNG seed |
| `OUTPUT_DIR` | | `./artifacts` | Results output directory |
| `TOKENIZER_PATH` | | (none) | Tokenizer: local dir or HF repo ID |
| `TOKENIZER_TRUST_REMOTE_CODE` | | `0` | Set to `1` to enable remote tokenizer code execution |
| `HF_TOKEN` | | (none) | HuggingFace token for gated/private model tokenizers |
| `HF_HOME` | | (image default) | Override HuggingFace cache directory (fixes permission errors) |

### 8.3 JSONL Prompt Schema Reference

Each scenario uses a JSONL (JSON Lines) file where each line is a single JSON record. The field names and structure depend on the `--custom-dataset-type`.

**MooncakeTrace schema** (used by `content_generation` and `rag_long_context`):

```jsonl
{"text_input": "Write a 500-word blog post about sustainable technology trends..."}
{"text_input": "Create a product description for an AI-powered customer service chatbot..."}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text_input` | string | ✓ | The prompt text sent as the user message to the chat endpoint |

Each record is replayed exactly once, in file order. This is the confirmed-working schema for single-turn scenarios.

**MultiTurn schema** (used by `conversational_chat` — known schema issue, see [Section 7.4](#74-known-issues--limitations)):

```jsonl
{"text_input": [{"role": "user", "content": "Hello, I need help..."}, {"role": "assistant", "content": "I'd be happy to help..."}, {"role": "user", "content": "My account was charged twice..."}]}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text_input` | array | ✓ | Array of message objects, each with `role` and `content` keys |

The exact schema expected by the installed AIPerf version may differ — the `multi_turn` dataset type is not yet confirmed working. See `docs/scenarios/model-selection.md` for current status.

### 8.4 Directory Structure Reference

```
genai-load-performance-testing/
├── docs/
│   ├── customer/
│   │   └── performance-guide.md          # This document
│   ├── scenarios/
│   │   ├── model-selection.md            # Scenario matrix & definitions
│   │   └── sizing.md                     # Sizing suite definitions
│   └── metrics/
│       ├── model-selection.md            # Model selection metrics table
│       └── sizing.md                     # Sizing metrics table
├── model-selection/
│   ├── scripts/
│   │   ├── run_content_generation.sh     # Content generation scenario script
│   │   ├── run_conversational_chat.sh    # Conversational chat scenario script
│   │   └── run_rag_long_context.sh       # RAG / long-context scenario script
│   ├── prompts/
│   │   ├── content_generation.jsonl      # 20 single-turn marketing prompts
│   │   ├── conversational_chat.jsonl     # 20 multi-turn chat sessions
│   │   └── rag_long_context.jsonl        # 18 long-context Q&A prompts
│   ├── k8s/
│   │   ├── run-test.sh                   # End-to-end orchestration script
│   │   ├── generate-configmaps.sh        # ConfigMap generator
│   │   ├── content-generation-job.yaml   # K8s Job manifest
│   │   ├── conversational-chat-job.yaml  # K8s Job manifest
│   │   ├── rag-long-context-job.yaml     # K8s Job manifest
│   │   └── results-pvc.yaml              # Shared results PVC (20Gi)
│   └── results/                          # ❌ Not yet created — commit output here
├── sizing/                               # ❌ Not yet implemented
├── CLAUDE.md                             # AI assistant context
└── README.md                             # Project overview
```

### 8.5 Kubernetes Resource Reference

Each test run in the `model-selection/k8s/` suite creates or uses the following resources in the target namespace:

| Resource Type | Name | Purpose | Created By |
|---------------|------|---------|------------|
| Namespace | `aiperf` (default) | Isolated environment for test execution | `run-test.sh` |
| Secret | `aiperf-hf-token` | HuggingFace token for gated model tokenizers (optional) | `run-test.sh` |
| ConfigMap | `aiperf-<scenario>-script` | Scenario bash script mounted into the Job container | `generate-configmaps.sh` |
| ConfigMap | `aiperf-<scenario>-prompts` | Prompt JSONL file mounted into the Job container | `generate-configmaps.sh` |
| PersistentVolumeClaim | `aiperf-model-selection-results` | Shared 20Gi volume for test result artifacts | `run-test.sh` (via `results-pvc.yaml`) |
| Job | `aiperf-<scenario>` | Runs the AIPerf test as a batch workload | `run-test.sh` (via Job YAML) |
| Pod | `aiperf-<scenario>-<hash>` | Created by the Job — executes the test | K8s scheduler (automatic) |

**Job template parameters to customize** (in each `*-job.yaml`):
- `image:` — AIPerf container image tag (default: `nvcr.io/nvidia/ai-dynamo/aiperf:0.10.0` — update as needed)
- `env.MODEL` / `env.URL` — target model identifier and endpoint base URL (required before applying)
- `resources.limits/requests` — CPU/memory per job pod (default limits: 2 CPU, 2GB RAM)
- `storageClassName` in `results-pvc.yaml` — set to your cluster's storage class

### 8.6 Metrics Calculation Reference

AIPerf records per-request telemetry in CSV format and computes aggregate statistics. Below is how each key metric is derived.

| Metric | Unit | Calculation | Source |
|--------|------|-------------|--------|
| **TTFT** (Time to First Token) | ms | Time from request send to receipt of first response token | Per-request CSV column |
| **TTST** (Time to Second Token) | ms | Time from first to second token (helps distinguish prompt processing from scheduling overhead) | Derived from first two token timestamps |
| **ITL** (Inter-Token Latency) | ms | Average time between consecutive tokens after the first token | Per-request CSV column |
| **End-to-End Latency** | ms | Total time from request to final token (or full response for non-streaming) | Per-request CSV column |
| **Output Token Throughput (per user)** | tok/s | `(total_output_tokens - 1) / (end_to_end_latency - ttft)` | Derived from per-request metrics |
| **System Output Token Throughput** | tok/s | Sum of all per-user throughputs at a given concurrency level | Aggregate across requests |
| **Goodput** | % | Percentage of requests where TTFT, ITL, and total latency all fall within configured SLA targets | Aggregate metric |
| **Success / Error Rate** | % | Percentage of requests completed without HTTP or streaming errors | Aggregate metric |
| **Request Throughput** | req/s | Total completed requests divided by test duration | Aggregate metric |

For the exact metric definitions, column names, and output format, see `docs/metrics/model-selection.md` and the AIPerf documentation.

### 8.7 Git Workflow for Reproducibility

The project uses Git as the single source of truth for both configuration and results, ensuring every test run is traceable back to a specific commit and AIPerf version.

**Commit structure:**

```
model-selection/results/<model>/<scenario>/<concurrency>/
├── <AIPerf CSV export>                        # Per-request metrics
├── <AIPerf JSON export>                       # Aggregated metrics + full test configuration
└── aiperf-version.txt                         # Pinned AIPerf version
```

**Best practices:**
1. **Pin the AIPerf version** — record `aiperf --version` output in each results directory or commit message.
2. **Commit scripts and results together** — a commit should contain both the scenario script version *and* the output it produced.
3. **Descriptive commit messages** — include model name, concurrency level, date, and any environmental notes (e.g., "llama-3-70b, concurrency=10, cluster with 4xA100, 2026-07-04").
4. **Tag significant milestones** — use Git tags for baseline results (e.g., `v1-baseline-llama3-70b`).
5. **No generated files in untracked changes** — the `.gitignore` excludes the `sample-script.sh` scratch file and any local artifacts outside the `results/` directory tree.

This approach ensures that any stakeholder can reproduce a given result by checking out the corresponding commit and re-running the script with the same AIPerf version.
