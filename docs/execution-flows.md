# Execution Flows

How a test actually runs, for each of the three entry paths. All paths converge on the
same per-scenario bash script (script-as-config), which issues the `aiperf profile`
invocation and produces the raw AIPerf export committed to Git.

## Overview

End-to-end flow shared by all entry paths: entry point → per-scenario script → AIPerf →
target endpoint → raw export → committed to Git.

```mermaid
flowchart LR
    subgraph ENTRY["Entry Paths"]
        NOTEBOOK["Jupyter Notebook<br/>interactive / reference"]
        K8SJOB["Kubernetes Job<br/>primary delivery"]
        JUMP["Jumphost<br/>planned - not built yet"]
    end

    SCRIPT["Per-Scenario Bash Script<br/>script-as-config<br/>single source of truth"]

    AIPERF["AIPerf<br/>aiperf profile"]

    LLM["OpenAI-Compatible Endpoint<br/>NIM, vLLM, TGI, SGLang, ..."]

    EXPORT["Raw AIPerf Export<br/>no processed report layer"]

    GIT["Git Repository<br/>scripts + run outputs committed,<br/>AIPerf version pinned"]

    NOTEBOOK --> SCRIPT
    K8SJOB --> SCRIPT
    JUMP -.-> SCRIPT

    SCRIPT --> AIPERF

    AIPERF -->|"Concurrent inference requests"| LLM
    LLM -->|"Streaming or non-streaming responses"| AIPERF

    AIPERF --> EXPORT
    EXPORT --> GIT
```

## Notebooks (interactive/reference)

`notebooks/model_selection_content_generation.ipynb` runs the Model Selection Content
Generation scenario end-to-end interactively. Reference material — not wired into either
suite's automation.

```mermaid
flowchart LR
    USER["Data Scientist / Performance Engineer"]

    subgraph JUPYTER["Jupyter Environment"]
        NOTEBOOK["Jupyter Notebook"]

        CONFIG["Experiment Configuration<br/>model, prompts, concurrency,<br/>request rate, ISL and OSL"]

        EXEC["Shell Cell or<br/>Python subprocess"]

        AIPERF["AIPerf<br/>aiperf profile"]

        RESULTS["AIPerf Result Artifacts"]

        ANALYSIS["Notebook Analysis<br/>plots, comparisons and reports"]

        NOTEBOOK --> CONFIG
        CONFIG --> EXEC
        EXEC --> AIPERF
        AIPERF --> RESULTS
        RESULTS --> ANALYSIS
        ANALYSIS --> NOTEBOOK
    end

    LOCATION{"Jupyter Location"}

    INTERNAL["Jupyter running<br/>inside Kubernetes"]

    EXTERNAL["Jupyter running<br/>outside Kubernetes"]

    DNS["Kubernetes DNS"]

    ENTRY["Ingress, Gateway or<br/>Internal Load Balancer"]

    subgraph K8S["On-Prem Kubernetes Cluster"]
        SERVICE["Kubernetes Service"]

        subgraph GPU_NODE["GPU Worker Node"]
            COMPAT["OpenAI-Compatible Endpoint<br/>for example:<br/>/v1/chat/completions"]

            TRT["Model-Serving Pod<br/>TensorRT-LLM"]
            VLLM["Model-Serving Pod<br/>vLLM"]
            TGI["Model-Serving Pod<br/>Hugging Face TGI"]
            SGLANG["Model-Serving Pod<br/>SGLang"]

            COMPAT --> TRT
            COMPAT --> VLLM
            COMPAT --> TGI
            COMPAT --> SGLANG
        end

        SERVICE --> COMPAT
    end

    USER --> NOTEBOOK
    AIPERF --> LOCATION

    LOCATION -->|"Inside cluster"| INTERNAL
    INTERNAL --> DNS
    DNS --> SERVICE

    LOCATION -->|"Outside cluster"| EXTERNAL
    EXTERNAL --> ENTRY
    ENTRY --> SERVICE

    SERVICE -->|"Streaming or non-streaming responses"| AIPERF
```

## Jumphost (planned — not built yet)

Native pip/binary install on a jumphost, no Docker. Calls the **same** per-scenario
scripts as the K8s path. Roadmap item; diagram describes the intended flow, not current
status.

```mermaid
flowchart LR
    USER["Performance Engineer"]

    subgraph JUMP["Jump Host / Bastion"]
        CFG["Test Configuration<br/>model, prompts, concurrency,<br/>request rate, ISL and OSL"]

        AIPERF["AIPerf<br/>aiperf profile"]

        RESULTS["Benchmark Results<br/>latency, TTFT, ITL,<br/>throughput and errors"]

        CFG --> AIPERF
        AIPERF --> RESULTS
    end

    subgraph NETWORK["Private Network Path"]
        FW["Firewall / Routing"]
        ENTRY["Ingress, Gateway or<br/>Internal Load Balancer"]
    end

    subgraph K8S["On-Prem Kubernetes Cluster"]
        SERVICE["Kubernetes Service"]

        subgraph GPU_NODE["GPU Worker Node"]
            COMPAT["OpenAI-Compatible Endpoint<br/>for example:<br/>/v1/chat/completions"]

            TRT["Model-Serving Pod<br/>TensorRT-LLM"]
            VLLM["Model-Serving Pod<br/>vLLM"]
            TGI["Model-Serving Pod<br/>Hugging Face TGI"]
            SGLANG["Model-Serving Pod<br/>SGLang"]

            COMPAT --> TRT
            COMPAT --> VLLM
            COMPAT --> TGI
            COMPAT --> SGLANG
        end

        SERVICE --> COMPAT
    end

    USER --> CFG

    AIPERF -->|"Concurrent inference requests"| FW
    FW --> ENTRY
    ENTRY --> SERVICE

    SERVICE -->|"Streaming or non-streaming responses"| ENTRY
    ENTRY --> FW
    FW --> AIPERF
```

## In-Cluster (Kubernetes Job) — primary delivery

K8s Job manifests under `model-selection/k8s/` and `sizing/k8s/` (sizing runs one Job per
ladder rung with a shared PVC and an error-rate circuit breaker between rungs).

```mermaid
flowchart LR
    USER["Performance Engineer / CI Pipeline"]

    subgraph K8S["On-Prem Kubernetes Cluster"]

        subgraph BENCH["Benchmark Namespace"]
            CONFIG["Test Configuration<br/>model, prompts, concurrency,<br/>request rate, ISL and OSL"]

            AIPERF["AIPerf Pod or Job<br/>aiperf profile"]

            RESULTS["Benchmark Results<br/>latency, TTFT, ITL,<br/>throughput and errors"]

            CONFIG --> AIPERF
            AIPERF --> RESULTS
        end

        DNS["Kubernetes DNS"]

        SERVICE["Kubernetes Service"]

        subgraph GPU_NODE["GPU Worker Node"]
            COMPAT["OpenAI-Compatible Endpoint<br/>for example:<br/>/v1/chat/completions"]

            TRT["Model-Serving Pod<br/>TensorRT-LLM"]
            VLLM["Model-Serving Pod<br/>vLLM"]
            TGI["Model-Serving Pod<br/>Hugging Face TGI"]
            SGLANG["Model-Serving Pod<br/>SGLang"]

            COMPAT --> TRT
            COMPAT --> VLLM
            COMPAT --> TGI
            COMPAT --> SGLANG
        end

        DNS --> SERVICE
        SERVICE --> COMPAT
    end

    USER -->|"Deploy Pod or Job"| CONFIG

    AIPERF -->|"Resolve internal service"| DNS
    AIPERF -->|"Concurrent inference requests"| SERVICE

    SERVICE -->|"Streaming or non-streaming responses"| AIPERF

    RESULTS -->|"Export or compare results"| USER
```
