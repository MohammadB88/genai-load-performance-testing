# LLM Performance Testing & Sizing Guide

## 1. Executive Summary

This document provides a comprehensive guide for running reproducible LLM performance tests using NVIDIA AIPerf on Kubernetes. The testing suite is backend-agnostic and works with any OpenAI-compatible endpoint (NIM, vLLM, TGI, etc.). It enables two primary workflows: **Model Selection** (choosing the right model for your use cases) and **Infrastructure Sizing** (determining the compute resources needed to meet your SLAs).

### 1.1 Goals & Objectives

- **Model Selection Excellence**: Identify optimal models that balance intelligence, speed, and cost for specific use cases
- **Infrastructure Optimization**: Determine precise compute resource requirements to maintain performance standards under load
- **User Experience Assurance**: Guarantee responsive, smooth interactions that meet user expectations
- **Cost Efficiency**: Right-size infrastructure to avoid over-provisioning while maintaining SLA compliance
- **Risk Mitigation**: Data-driven decisions reduce deployment failures and performance regressions
- **Scalability Planning**: Understand capacity limits and growth requirements before production launch
- **Competitive Performance**: Validate that chosen models perform competitively against alternatives
- **Production Readiness**: Ensure systems are validated and ready for real-world traffic patterns

### 1.2 Business Value

- **Cost Optimization**: Reduce infrastructure spend by 20-40% through precise capacity planning
- **Performance Guarantees**: Establish SLAs backed by empirical data, not theoretical estimates
- **Faster Time-to-Market**: Accelerate deployment decisions with clear performance data
- **Reduced Downtime Risk**: Identify bottlenecks before they impact production users
- **Better Resource Allocation**: Direct compute resources to high-impact workloads
- **Vendor Negotiation Leverage**: Use performance data in vendor discussions and SLA negotiations
- **Customer Satisfaction**: Deliver consistent user experiences that build trust
- **Future-Proofing**: Understand scaling requirements for planned growth
- **Budget Planning**: Accurate forecasting of infrastructure costs as user base grows
- **Technical Debt Prevention**: Avoid costly re-architecting due to poor initial sizing decisions

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

**NVIDIA AIPerf** *(Note: Version TBD - to be updated)*
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

*[Content to be finalized - see revision plan for approved structure]*

---

## 4. Quick Start Guide

*[Content to be finalized - see revision plan for approved structure]*

---

## 5. Running Model Selection Tests

*[Content to be finalized - see revision plan for detailed structure]*

---

## 6. Understanding Results

*[Content to be developed]*

---

## 7. Troubleshooting & FAQ

*[Content to be developed]*

---

## 8. Technical Reference

*[Content to be developed]*