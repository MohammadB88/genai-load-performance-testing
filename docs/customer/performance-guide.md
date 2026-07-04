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
- **Default Limits**: 2 CPUs, 4GB RAM per AIPerf job (suitable for most scenarios)
- **Adjustment Guidelines**: 
  - High-concurrency tests: Increase resources proportionally
  - Large-context scenarios: May require additional memory
  - Scale based on your cluster capacity and test requirements
- **Storage**: 10GB persistent volume per test job (configurable based on expected output size)

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
kubectl run image-test --image=nvcr.io/nvidia/aiperf:latest --rm -it --restart=Never -- \
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
- Only 3 model-selection scenarios are functional: conversational_chat, rag_long_context, content_generation
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

#### Step 1: Set Up API Credentials

Create a Kubernetes Secret with your LLM endpoint credentials:

```bash
# Create secret with your API key
kubectl create secret generic aiperf-credentials \
  --from-literal=api-key='your-api-key-here' \
  --from-literal=endpoint-url='https://your-llm-endpoint.com:8000' \
  --from-literal=model-name='your-model-name'

# Verify secret creation (should show: secret/aiperf-credentials created)
kubectl get secret aiperf-credentials
```

**Success Indicator**: You should see `secret/aiperf-credentials created` and `kubectl get secret aiperf-credentials` should list your secret.

#### Step 2: Verify Test Scripts

Ensure the content generation scenario scripts exist:

```bash
# List available scenario scripts
ls model-selection/

# Verify content generation script exists
ls model-selection/run_content_generation.sh

# Verify prompts exist
ls model-selection/prompts/content_generation.jsonl
```

**Success Indicator**: You should see `run_content_generation.sh` and `content_generation.jsonl` in the listings.

### 4.4 Running Your First Test

#### Step 1: Execute the Quick Start Job

For this quick start, we'll run a simplified version of the content generation test:

```bash
# Run the content generation scenario with default parameters
kubectl apply -f model-selection/k8s/content-generation-job.yaml

# Monitor job startup
kubectl get pods -l job-name=content-generation-test
```

**Success Indicator**: You should see a pod with status `Running` or `Completed` after 30-60 seconds.

#### Step 2: Monitor Test Progress

Watch the job execution:

```bash
# View job status
kubectl get job content-generation-test

# View pod logs to see test progress
kubectl logs -f job/content-generation-test
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
{"prompt": "Write a 500-word blog post about sustainable technology trends for 2024, focusing on renewable energy innovations."}

{"prompt": "Create a product description for an AI-powered customer service chatbot, highlighting key features and benefits for small businesses."}

{"prompt": "Draft a marketing email announcing a new cloud infrastructure service, targeting CTOs and IT directors at mid-sized companies."}

{"prompt": "Write a technical whitepaper abstract about machine learning model optimization techniques for edge computing devices."}

{"prompt": "Generate a social media campaign plan for a B2B SaaS product launch, including content calendar and platform strategy."}
```

**Note**: These prompts test the model's ability to generate high-quality, business-relevant content from brief inputs. Your actual tests may use custom prompts specific to your use cases.

### 4.6 Viewing Results

#### Step 1: Access Test Results

Results are stored in the persistent volume attached to the test pod:

```bash
# Find the completed pod
POD_NAME=$(kubectl get pods -l job-name=content-generation-test -o jsonpath='{.items[0].metadata.name}')

# Copy results from the pod
kubectl cp $POD_NAME:/results ./quick-start-results --container=aiperf

# List downloaded results
ls quick-start-results/
```

**Success Indicator**: You should see CSV and JSON files in the `./quick-start-results/` directory.

#### Step 2: Understand Result Structure

Typical output files include:
- `results_*.csv`: Raw performance metrics (detailed, per-request data)
- `summary_*.json`: Aggregated metrics and test configuration
- `configuration_*.json`: Complete test parameters for reproducibility

**Key Files to Examine:**
```bash
# View the summary file
cat quick-start-results/summary_*.json

# View a sample of the detailed results
head -n 20 quick-start-results/results_*.csv
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

### 5.2 Multi-Model Comparison Workflow (Default Approach)
Our recommended default methodology uses a **round-robin by concurrency level** approach:
1. Test all model candidates at Concurrency = 1  
2. Test all model candidates at Concurrency = 5  
3. Test all model candidates at Concurrency = 10  
4. Test all model candidates at Concurrency = 25  
- **Why this approach?** Direct comparison at each load level makes it easy to see relative scaling characteristics  
- **Customization**: For specific use cases, you may focus on particular scenarios only  
- **Consistency Critical**: Maintain identical cluster state, time of day, and network conditions  

### 5.3 Content Generation Scenario  
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

### 5.4 Conversational Chat Scenario  
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

### 5.5 RAG / Long-Context Scenario  
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
# Similar setup to content generation, but with different script
kubectl apply -f model-selection/k8s/rag_long_context-job.yaml
```

**Duration Expectation**: 30-60 minutes per concurrency level (often longest due to context processing complexity)

**Results Interpretation**:  
TTFT: "Lower indicates faster initial context processing"  
ITL: "Lower improves answer delivery smoothness"  
Context Utilization Effectiveness: "Higher suggests better use of provided information" (qualitative)  
Request Completion Rate: "Higher indicates reliable complex query handling"  
- Qualitative note: Evaluate whether responses actually use relevant context points  

### 5.6 Common Configuration Parameters  
**Required Parameters** (must be set for all tests):  
- `MODEL`: Target model identifier/name  
- `URL`: LLM endpoint base URL (e.g., `http://localhost:8000`)  
- `ENDPOINT_TYPE`: Usually "openai" for OpenAI-compatible APIs  
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

### 5.7 Multi-Model Comparison Workflow  
**Primary Use Case**: Selecting optimal model from candidates based on performance  
**Recommended Process** (assuming round-robin testing):  
1. Define model candidates (2-4 models for meaningful comparison)  
2. Prepare identical test environment (same cluster, time of day, network conditions)  
3. For each concurrency level [1, 5, 10, 25]:  
   a. Test Model A at current concurrency  
   b. Test Model B at current concurrency  
   c. Test Model C at current concurrency (if applicable)  
   d. [Optional] Re-test reference model to check for drift  
4. Collect and normalize results for comparison  
- **Comparison Framework**:  
  - Create tables showing metrics side-by-side across models/concern levels  
  - Use radar/spider charts for multi-metric comparison  
  - Apply weighting based on business priorities (latency vs. throughput vs. quality)  
  - Identify Pareto-optimal models (no worse on any metric, better on at least one)  
- **Decision Guidance**:  
  - Latency-sensitive apps: Prioritize low TTFT/ITL  
  - Throughput-focused apps: Prioritize high goodput/request rate  
  - Quality-sensitive apps: May accept higher latency for better output fidelity  
  - Document rationale for selection to support future re-evaluation  

### 5.8 Troubleshooting Model Selection Tests  
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

### 5.9 Summary of Findings  
- The testing framework enables data-driven model selection through standardized, reproducible evaluations  
- Business value comes from quantifying performance across UX-relevant metrics rather than subjective impressions  
- Results should inform both model choice and infrastructure requirements for production deployment  
- All three implemented scenarios contribute distinct insights: content generation for output quality, chat for multi-turn fluency, RAG for context handling  
- **Note**: This section focuses on operational testing; output quality validation requires separate human evaluation filters

*[Content to be finalized - see revision plan for detailed structure]*

---

## 6. Understanding Results

### 6.1 Overview of AIPerf Output
- Brief overview of the provided output format and output files (e.g., CSV/JSON files written to `./artifacts/<scenario>/`).
- Reference to the `metrics-directory` where metric summary tables are stored for quick reference.

### 6.2 Core Metrics Explained
- Include a placeholder chart/graph illustrating typical TTFT and ITL versus concurrency for a "good" model vs. a "bad" model.
- Reference the metric tables stored under the `metrics-directory`; these tables contain column headings such as `scenario`, `concurrency`, `ttft_ms`, `itl_ms`, `goodput_pct`, `success_rate`.

### 6.3 Reading Latency‑vs‑Concurrency Curves
- Provide a simple heuristic for locating the “knee”: look for where the latency increase per added concurrency exceeds a noticeable threshold.
- **Notice**: Readers can dive deeper into the three zones (Linear, Knee, Saturation) if desired; this notice hints at the optional detailed explanation.

### 6.4 Mapping Results to Service‑Level Agreements (SLAs)
- High‑level guidance: use your SLA (e.g., 95 % of requests < 2 s TTFT) to read off the maximum sustainable concurrency from the latency‑vs‑concurrency curve.
- **Notice (Option B)**: A placeholder example table could show concurrency, 95th‑percentile TTFT, and SLA compliance status.

### 6.5 Model‑Comparison Framework
- Recommend testing all candidates at each concurrency level (1/5/10/25) and presenting side‑by‑side tables (placeholder) of TTFT, ITL, Goodput, and Success Rate.
- **Notice (Option D)**: A brief decision‑tree can be added to help prioritize metrics based on business focus (latency‑sensitive, throughput‑sensitive, quality‑sensitive).

### 6.6 Preliminary Infrastructure Insights (Placeholder)
- Note that the observed knee in model‑selection curves provides a rough upper bound for a single‑node/GPU estimate; full infrastructure sizing will be covered in a future version (Section 8 or a dedicated sizing guide).

### 6.7 Validating Result Quality
- Quick reminder to verify that results look reasonable before proceeding.
- **Notice (Option A)**: Short bullet list – check token counts, spot‑check responses for basic coherence, scan logs for errors.
- **Notice (Option B)**: More detailed checklist (e.g., `grep -i error *.log`, verify input/output token counts) can be added later.

### 6.8 Using Results for Next Steps
- Minimal wrap‑up: document the chosen model and note that it will feed into the upcoming infrastructure‑sizing suite.
- **Notice (Option A)**: Short checklist – archive results, write model‑selection rationale, prepare sizing suite.
- **Notice (Option B)**: Expanded checklist can be added later (e.g., stakeholder review, baseline establishment).

---

## 7. Troubleshooting & FAQ

*[Content to be developed]*

---

## 8. Technical Reference

*[Content to be developed]*