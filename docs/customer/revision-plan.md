# Customer Documentation Revision Plan

> Generated: 2026-07-04
> Status: Section 1 (Executive Summary) complete, Section 2 (Technical Overview) complete, Section 3 (Prerequisites) complete, Section 4 (Quick Start) complete, Section 5 (Running Model Selection Tests) planned

---

## Target Document

**File:** `docs/customer/performance-guide.md`
**Format:** Single comprehensive guide for engineers (with intro/goals/objectives)
**Scope:** Currently implemented features only (3 model-selection scenarios)
**Excluded:** Unimplemented scenarios (will be added in future versions)

---

## Proposed Document Structure

| # | Section | Status |
|---|---------|--------|
| 1 | Executive Summary | ✓ Approved |
| 2 | Technical Overview | ✓ Approved |
| 3 | Prerequisites & Environment Setup | ✓ Approved |
| 4 | Quick Start Guide | ✓ Approved |
| 5 | Running Model Selection Tests | 📋 Planned |
| 6 | Understanding Results | ❌ Not yet started |
| 7 | Troubleshooting & FAQ | ❌ Not yet started |
| 8 | Technical Reference | ❌ Not yet started |

---

## Section 1: Executive Summary

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

- **Two-Phase Testing Approach**:
  - **Phase 1: Model Selection** (1-3 days per model candidate)
    - Compare 2+ models across workload profiles
    - Evaluate UX-relevant metrics (TTFT, ITL, Goodput)
    - Identify best model for your use cases
  - **Phase 2: Infrastructure Sizing** (3-5 days per configuration)
    - Test selected model against concurrency ladder
    - Identify capacity limits and "knee of the curve"
    - Calculate required hardware footprint

- **Resource Requirements**:
  - **Compute**: Access to representative production-like hardware
  - **Network**: Stable connectivity to LLM endpoints
  - **Time**: 1-2 weeks for complete analysis (depending on complexity)
  - **Expertise**: DevOps/SRE for Kubernetes deployment and configuration

- **Deliverables**:
  - **Raw Performance Data**: Complete AIPerf exports for all test scenarios
  - **Analysis Reports**: Detailed metrics breakdown and interpretation
  - **Model Recommendations**: Evidence-based model selection guidance
  - **Performance Baselines**: Establish current performance benchmarks
  - **[PLACEHOLDER: Infrastructure Blueprints]**: Detailed hardware sizing recommendations (coming soon)

---

## Section 2: Technical Overview (Proposed)

### Proposed Subsections

1. **Architecture Overview**
2. **Testing Methodology**
3. **Key Technical Concepts**
4. **Technology Stack**

### Open Questions for Customer

1. **Architecture Detail Level**: High-level (component boxes and arrows) or specific implementation details?
2. **Methodology Focus**: Emphasis on "why" we test this way or "how" the testing works technically?
3. **Technology Stack**: Mention specific versions or keep it version-agnostic?
4. **Real-World Simulation**: Include examples of workload profiles mapping to actual user behaviors?
5. **Reproducibility**: Brief mention or detailed explanation of Git-based versioning?
6. **Backend Agnosticism**: Explain how tests work across different backends (NIM, vLLM, TGI)?

---

## Section 5: Running Model Selection Tests (Detailed Plan)

### Proposed Subsections (Progressive Order)

1. **Model Selection Overview** — Purpose, business value, how results inform decisions
2. **Testing Strategy** — Baseline testing, flexible concurrency with suggested 1/5/10/25 ladder, methodology rationale
3. **Content Generation Scenario** — Business use cases, critical parameters + parameters used, running the test (parameter explanations), per-scenario time estimate, placeholder for sample outputs, interpreting results (detailed with room for refinement)
4. **Conversational Chat Scenario** — Business use cases, critical parameters + parameters used, multi-turn handling, think-time configuration, running the test, per-scenario time estimate, placeholder for sample outputs, interpreting results
5. **RAG / Long-Context Scenario** — Business use cases, critical parameters + parameters used, large context handling, running the test, per-scenario time estimate, placeholder for sample outputs, interpreting results
6. **Common Configuration Parameters** — Critical parameters shared across scenarios, parameters actually used, parameter explanations (not script editing), best practices
7. **Multi-Model Comparison Workflow** — Detailed workflow (primary use case), systematic testing approach, results comparison methodology, decision-making framework
8. **Troubleshooting Model Selection Tests** — Scenario-specific issues, common configuration problems

### Key Content Decisions

| Decision | Choice |
|----------|--------|
| Scenario organization | Progressive: content_generation → conversational_chat → rag_long_context |
| Concurrency approach | Flexible with suggested 1/5/10/25 ladder |
| Multi-model comparison | Detailed workflow (primary use case) |
| Sample outputs | Placeholders only (customer adds real results later) |
| AIPerf flags | Critical flags only + flags actually used in 3 scenarios |
| Customization approach | Parameter explanations focus (not script editing) |
| Scenario interpretation | Detailed business-focused with room for refinement |
| Duration estimates | Per-scenario time estimates |

### Open Items Requiring Input

1. **Parameter investigation**: Need to examine existing scenario scripts (`run_content_generation.sh`, `run_conversational_chat.sh`, `run_rag_long_context.sh`) to identify exact AIPerf flags and values used
2. **Business metric thresholds**: What constitutes "good" TTFT/ITL/goodput for each scenario type?
3. **Multi-model comparison structure**: Test all models at same concurrency, or test each model independently?
4. **Duration estimation basis**: Typical LLM endpoint performance, or specific timing expectations?
5. **Placeholder detail level**: Describe exact CSV columns and JSON structure, or keep high-level?

### Customer Feedback Received

- Progressive scenario ordering confirmed ✓
- Flexible concurrency with suggested 1/5/10/25 ladder ✓
- Detailed multi-model comparison workflow ✓
- Placeholders for sample outputs ✓
- Critical AIPerf flags + scenario-used flags ✓
- Parameter explanations (not script editing) ✓
- Detailed business interpretation with refinement room ✓
- Per-scenario duration estimates ✓

---

## Section 3: Prerequisites & Environment Setup (Approved)

### Customer Feedback Incorporated

| Decision | Choice |
|----------|--------|
| Container images | NGC and private registry options |
| Default namespace | `aiperf` |
| Configuration management | K8s Secrets (with vault integration notice) |
| Resource limits | Defaults provided (2 CPU, 4GB RAM) with adjustment guidelines |
| Network requirements | Model-APIs must be reachable from testing environment |
| Storage | Persistent storage for results |
| Troubleshooting | Dedicated section with common issues (API reachability, missing scripts/prompts, image pulls, resource constraints, PVC binding) |
| Timeline estimates | Broad with customer-dependency note |

---

## Section 4: Quick Start Guide (Approved)

### Customer Feedback Incorporated Customer Feedback

| Decision | Choice |
|----------|--------|
| Scenario | content_generation (with note about future customization) |
| Customization | Default parameters only, mention future features |
| Result access | Persistent volume copy method (customer will develop retrieval process) |
| Success indicators | Checkpoints at each step |
| Sample prompts | 5 examples from content_generation.jsonl |
| Duration | Generous estimate (30-60 minutes) |

---

## Decisions Made So Far

| Decision | Choice |
|----------|--------|
| Target audience | Engineers who will run the tests; with intro/goals/objectives for completeness |
| Technical depth | Implementation details (K8s configuration, deployment instructions) |
| Priority areas | Clarity & Structure, Technical accuracy, Results interpretation, Executive summary |
| Examples | Include detailed examples and placeholders (customer fills after test runs) |
| Structure | Single comprehensive guide |
| Implemented scenarios | Document only 3 implemented model-selection scenarios (content_generation, conversational_chat, rag_long_context) |
| Unimplemented scenarios | Ignore; will be added in future documentation versions |
| Sample outputs | Add placeholders |
| AIPerf flags | Critical flags only + flags actually used in implemented scenarios |
| **Section 3: Container images** | NGC and private registry |
| **Section 3: Default namespace** | `aiperf` |
| **Section 3: Config management** | K8s Secrets (with vault integration notice) |
| **Section 3: Resource limits** | Defaults (2 CPU, 4GB RAM) with adjustment guidelines |
| **Section 3: Network** | Model-APIs must be reachable from testing environment |
| **Section 3: Storage** | Persistent storage |
| **Section 3: Troubleshooting** | Dedicated section with common issues |
| **Section 3: Timeline** | Broad estimates with customer-dependency note |
| **Section 4: Quick start scenario** | content_generation (with future customization note) |
| **Section 4: Customization** | Default parameters only |
| **Section 4: Result access** | Persistent volume copy |
| **Section 4: Success indicators** | Checkpoints at each step |
| **Section 4: Sample prompts** | 5 examples from content_generation.jsonl |
| **Section 4: Duration** | 30-60 minutes generous estimate |
| **Section 5: Scenario order** | Progressive: content_generation → conversational_chat → rag_long_context |
| **Section 5: Concurrency** | Flexible with suggested 1/5/10/25 ladder |
| **Section 5: Multi-model comparison** | Detailed workflow (primary use case) |
| **Section 5: Sample outputs** | Placeholders only |
| **Section 5: AIPerf flags** | Critical flags + scenario-used flags only |
| **Section 5: Customization focus** | Parameter explanations (not script editing) |
| **Section 5: Interpretation** | Detailed business-focused with refinement room |
| **Section 5: Duration estimates** | Per-scenario time estimates |

---

## Remaining Work

- [x] Section 2: Technical Overview
- [ ] Section 3: Prerequisites & Environment Setup
- [ ] Section 4: Quick Start Guide
- [ ] Section 5: Running Model Selection Tests
  - [ ] 5.1 Model Selection Overview
  - [ ] 5.2 Testing Strategy
  - [ ] 5.3 Content Generation Scenario
  - [ ] 5.4 Conversational Chat Scenario
  - [ ] 5.5 RAG / Long-Context Scenario
  - [ ] 5.6 Common Configuration Parameters
  - [ ] 5.7 Multi-Model Comparison Workflow
  - [ ] 5.8 Troubleshooting
- [ ] Section 6: Understanding Results
- [ ] Section 7: Troubleshooting & FAQ
- [ ] Section 8: Technical Reference
- [ ] Final review and polish
- [ ] Update README.md to reference new customer guide

---

## Original Draft Backup (`performance-guide.md`)

Preserved as of 2026-07-03 before revision.

```
# LLM Performance Testing & Sizing Guide

## 1. Executive Summary

This document outlines the performance benchmarking and infrastructure sizing process for your Large Language Model (LLM) deployment. The primary objective is to ensure that the selected model and hosting infrastructure provide a seamless user experience while remaining cost-effective and scalable.

### Objectives
The testing is divided into two critical phases:
- **Model Selection**: Determining which model provides the optimal balance of intelligence and speed for your specific use cases.
- **Infrastructure Sizing**: Determining the exact amount of compute resources (GPUs/Memory) required to maintain performance standards under your expected peak user load.

---

## 2. Performance Methodology

We utilize **NVIDIA AIPerf**, an industry-standard benchmarking tool, to generate reproducible and objective performance data. Unlike simple "average" tests, our methodology simulates real-world traffic patterns to identify precisely where a system succeeds or fails.

### Workload Profiles
We don't test with a single generic prompt. Instead, we use **six distinct workload profiles** tailored to your business operations (e.g., short queries, long-form summarization, and multi-turn agentic workflows). Each profile defines:
- **Input Sequence Length (ISL)**: The typical size of the prompt.
- **Output Sequence Length (OSL)**: The expected length of the model's response.
- **Think-Time**: Simulated pauses between user turns to mimic human interaction.

### Testing Approaches
- **The UX Sweep (Model Selection)**: We test a range of low-to-moderate concurrency (1, 5, 10, 25 users). This tells us how the model "feels" to an individual user.
- **The Capacity Ladder (Sizing)**: We push the system through a rigorous concurrency ladder (up to 200 users). This allows us to find the "knee of the curve"—the exact point where the hardware is saturated and latency begins to spike.

---

## 3. Technical Setup & Deployment

To ensure consistency, we deploy the testing environment using a containerized version of AIPerf on a Kubernetes (K8s) cluster. This decouples the testing tool from the model hosting infrastructure, preventing the tester itself from becoming a bottleneck.

### Deploying the Test Environment
We use the official NVIDIA AIPerf image. The deployment is typically handled as a K8s Job to ensure that the test runs to completion and the logs are captured.

### Environment Preparation
Before running tests, the following K8s resources must be configured to allow AIPerf to communicate with your LLM endpoint:

#### 1. API Secrets
To secure your API keys, create a Kubernetes secret. This prevents keys from being exposed in the scenario scripts.
```
kubectl create secret generic aiperf-secrets \
  --from-literal=API_KEY=your_api_key_here \
  --from-literal=API_ENDPOINT=https://your-llm-endpoint.com
```

#### 2. Configuration Maps
We use ConfigMaps to store non-sensitive environment variables, such as model names or version tags.
```
kubectl create configmap aiperf-config \
  --from-literal=MODEL_NAME=meta-llama-3-70b-instruct \
  --from-literal=AIPERF_VERSION=v1.0.0
```

### Executing the Tests
Once the environment is prepared, the tests are triggered by executing the scenario bash scripts within the AIPerf container. 

Example of running a sizing test:
```
# Apply the K8s Job manifest
kubectl apply -f sizing-job.yaml

# Monitor the progress
kubectl logs -f job/sizing-workload-01
```
The results are exported as raw CSV/JSON files, which are then collected and analyzed to produce the performance curves.

---

## 4. Key Performance Indicators (KPIs)

---

## 4. Key Performance Indicators (KPIs)

To understand the quality of the user experience and the capacity of the hardware, we track a comprehensive set of metrics. We categorize these into **UX Quality** (how it feels) and **System Capacity** (how it scales).

### UX Quality Metrics (Model Selection)
These metrics determine if a model is suitable for a human-facing interface.

| Metric | What it is | Why it matters |
| :--- | :--- | :--- |
| **TTFT** (Time to First Token) | The time between sending a request and seeing the first word appear. | **Perceived Responsiveness.** High TTFT makes the system feel "laggy" or frozen. |
| **TTST** (Time to Second Token) | The time it takes for the second token to arrive. | **Scheduling Overhead.** Helps us identify if the delay is in the initial prompt processing or the scheduler. |
| **ITL** (Inter-Token Latency) | The time between each subsequent token generated. | **Reading Fluidity.** Prevents "stuttering" text; ensures a natural reading pace. |
| **Goodput** | The % of requests that meet all latency goals (TTFT, ITL, and Total Latency) simultaneously. | **The "Gold Standard".** A model may have a fast average speed, but low goodput means many users are still having a poor experience. |
| **End-to-End Latency** | The total time from request to the final token. | **Batch/API Efficiency.** Critical for non-streaming use cases where the user waits for the full response. |

### System Capacity Metrics (Infrastructure Sizing)
These metrics define the physical limits of your hardware deployment.

| Metric | What it is | Why it matters |
| :--- | :--- | :--- |
| **System Throughput** | Total tokens generated per second across all users. | **Raw Power.** Defines the absolute ceiling of the current hardware configuration. |
| **Request Throughput (RPS)** | The number of completed requests per second. | **Request Density.** Helps distinguish if the system is struggling with many small requests or a few massive ones. |
| **GPU Utilization** | The percentage of GPU compute and memory (KV Cache) being used. | **Bottleneck Identification.** Tells us if the system is limited by compute power or memory capacity. |
| **Error Rate under Load** | The percentage of failed requests as concurrency increases. | **Stability.** Distinguishes a "slow" system from one that is crashing under pressure. |

---

## 5. Interpreting the Results

---

## 4. Interpreting the Results

Performance is not a single number, but a curve. As more users enter the system (concurrency increases), the available compute resources are split.

### The "Knee" of the Curve
In our sizing reports, you will see latency plotted against concurrency.
- **Linear Zone**: Latency remains stable; the system is comfortably under-utilized.
- **The Knee**: The point where latency begins to rise sharply. This is the **maximum sustainable capacity**.
- **Saturation Zone**: Latency spikes dramatically. At this point, users will experience significant delays, and the system may begin to fail.

### Mapping to SLAs
We map these results against your Service Level Agreements (SLAs). For example, if your business requirement is *"95% of users must see a response in under 2 seconds,"* we identify the concurrency level where that threshold is breached.

---

## 5. Recommendations & Next Steps

Based on the data gathered from the suites, we provide two primary deliverables:

### Model Recommendation
We analyze the **Model Selection** data to recommend a model that meets your quality needs while staying within the "Fluidity" range of ITL and the "Responsiveness" range of TTFT.

### Infrastructure Blueprint
Using the **Sizing** data, we calculate the required hardware footprint.
- **Current Capacity**: How many users your current setup can handle before hitting the "knee."
- **Target Scaling**: The number of additional GPUs or nodes required to support your projected peak growth while maintaining your SLAs.

---

## 6. Appendix: Test Parameters

The following parameters are applied across our six workload profiles to ensure the tests reflect your actual production environment:

- **Input Sequence Length (ISL)**: Mimics your typical prompt sizes.
- **Output Sequence Length (OSL)**: Mimics your typical response requirements.
- **Turn Count**: Simulates multi-turn conversations to test context window performance.
- **Think-Time**: Adds realistic human delays to prevent "unrealistic" robotic hammering of the API.
```
