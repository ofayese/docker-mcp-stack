#!/bin/bash
# Benchmark script for Docker MCP Stack
# This script provides functions to test and compare model performance

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
REPORT_DIR="$ROOT_DIR/reports/benchmarks"

# Import utility scripts
# shellcheck disable=SC1091
source "$UTILS_DIR/validation.sh"

# Test prompts for different benchmark categories
declare -A TEST_PROMPTS
TEST_PROMPTS["general"]="Explain the concept of artificial intelligence in simple terms."
TEST_PROMPTS["reasoning"]="If a train travels at 120 km/h and needs to cover a distance of 450 km, how long will the journey take? Explain your reasoning step by step."
TEST_PROMPTS["knowledge"]="Describe the process of photosynthesis and why it's important for life on Earth."
TEST_PROMPTS["creativity"]="Write a short poem about the beauty of nature and technological progress coexisting."
TEST_PROMPTS["code"]="Write a function in Python that checks if a string is a palindrome, with comments explaining the logic."
TEST_PROMPTS["instruction"]="Summarize the following text in 3 bullet points: The Industrial Revolution was a period of rapid industrialization that fundamentally changed how people lived and worked. It began in Great Britain in the mid-18th century and spread to other parts of Europe and North America. The transition included going from hand production methods to machines, new chemical manufacturing processes, iron production, improved efficiency of water power, the development of machine tools, and the rise of the mechanized factory system."

# Function to benchmark a single model
benchmark_model() {
    local model="$1"
    local port="$2"
    local prompt_category="${3:-general}"
    local max_tokens="${4:-200}"
    local temperature="${5:-0.7}"
    local repetitions="${6:-3}"
    
    log_info "Benchmarking model: $model on port $port (category: $prompt_category)"
    
    # Check if model container is running
    local container_name="model-runner-${model//./-}"
    if ! docker ps --format '{{.Names}}' | grep -q "$container_name"; then
        log_error "Model container $container_name is not running"
        return 1
    fi
    
    # Get prompt from category
    local prompt="${TEST_PROMPTS[$prompt_category]}"
    if [[ -z "$prompt" ]]; then
        log_error "Unknown prompt category: $prompt_category"
        log_error "Available categories: ${!TEST_PROMPTS[*]}"
        return 1
    fi
    
    log_info "Using prompt: \"$prompt\""
    log_info "Parameters: max_tokens=$max_tokens, temperature=$temperature"
    log_info "Running $repetitions repetitions..."
    
    local results=()
    local total_time=0
    local total_tokens=0
    
    for ((i=1; i<=repetitions; i++)); do
        log_info "Repetition $i/$repetitions..."
        
        # Start timer
        local start_time
        start_time=$(date +%s.%N)
        
        # Make API call
        local response
        response=$(curl -s "http://localhost:$port/engines/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"ai/$model\",
                \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
                \"max_tokens\": $max_tokens,
                \"temperature\": $temperature
            }")
        
        # End timer
        local end_time
        end_time=$(date +%s.%N)
        
        # Calculate duration
        local duration
        duration=$(echo "$end_time - $start_time" | bc)
        
        # Extract tokens generated from response
        local tokens=0
        if [[ "$response" == *"usage"* ]]; then
            tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        fi
        
        # Store results
        results+=("$duration")
        total_time=$(echo "$total_time + $duration" | bc)
        total_tokens=$(echo "$total_tokens + $tokens" | bc)
        
        log_info "Repetition $i complete: ${duration}s, $tokens tokens generated"
        
        # Add a small delay between repetitions
        if [[ $i -lt $repetitions ]]; then
            sleep 2
        fi
    done
    
    # Calculate average time and tokens per second
    local avg_time
    avg_time=$(echo "scale=3; $total_time / $repetitions" | bc)
    
    local avg_tokens
    avg_tokens=$(echo "scale=1; $total_tokens / $repetitions" | bc)
    
    local tokens_per_second
    tokens_per_second=$(echo "scale=2; $avg_tokens / $avg_time" | bc)
    
    log_info "Benchmark results for $model:"
    log_info "  Average time: ${avg_time}s"
    log_info "  Average tokens: $avg_tokens"
    log_info "  Tokens per second: $tokens_per_second"
    
    # Return results as a formatted string
    echo "$model,$prompt_category,$avg_time,$avg_tokens,$tokens_per_second"
    
    return 0
}

# Function to compare multiple models
compare_models() {
    log_info "Comparing models..."
    
    # Load environment variables
    if [[ -f "$ROOT_DIR/.env" ]]; then
        set -a
        source "$ROOT_DIR/.env"
        set +a
    fi
    
    # Parameters
    local prompt_category="${1:-general}"
    local max_tokens="${2:-200}"
    local temperature="${3:-0.7}"
    local repetitions="${4:-3}"
    
    # Create reports directory if it doesn't exist
    mkdir -p "$REPORT_DIR"
    
    # Generate report filename with timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local report_file="$REPORT_DIR/benchmark-$prompt_category-$timestamp.csv"
    
    # Create CSV header
    echo "Model,Category,AvgTime(s),AvgTokens,TokensPerSecond" > "$report_file"
    
    # Get running model containers
    local model_containers
    model_containers=$(docker ps --format '{{.Names}}' | grep "model-runner")
    
    # If no models are running, error and return
    if [[ -z "$model_containers" ]]; then
        log_error "No model containers are running"
        log_error "Please start at least one model container before benchmarking"
        return 1
    fi
    
    # List of successfully benchmarked models
    local benchmarked_models=()
    
    # Benchmark each model
    for container in $model_containers; do
        # Extract model name from container name
        local model="${container#model-runner-}"
        model="${model//-/.}"
        
        # Determine port from model name
        local var_name="MODEL_PORT_${model^^}"
        var_name="${var_name//-/_}"
        var_name="${var_name//./_}"
        
        if [[ -z "${!var_name+x}" ]]; then
            log_warn "Port for model $model not found in environment variables"
            log_warn "Skipping benchmark for model $model"
            continue
        fi
        
        local port="${!var_name}"
        
        log_info "Benchmarking model $model on port $port..."
        
        # Run benchmark
        local result
        if result=$(benchmark_model "$model" "$port" "$prompt_category" "$max_tokens" "$temperature" "$repetitions"); then
            # Append result to CSV
            echo "$result" >> "$report_file"
            benchmarked_models+=("$model")
        else
            log_error "Failed to benchmark model $model"
        fi
    done
    
    # Check if any models were successfully benchmarked
    if [[ ${#benchmarked_models[@]} -eq 0 ]]; then
        log_error "No models were successfully benchmarked"
        return 1
    fi
    
    log_info "✅ Benchmark complete"
    log_info "Models benchmarked: ${benchmarked_models[*]}"
    log_info "Results saved to: $report_file"
    
    # Display results in a formatted table
    log_info "Benchmark Results Summary:"
    echo "-------------------------------------------------------"
    echo "| Model            | Category | Avg Time | Tokens/sec |"
    echo "-------------------------------------------------------"
    
    # Sort results by tokens per second (fastest first)
    sort -t, -k5,5nr "$report_file" | tail -n +2 | while IFS=, read -r model category avg_time _ tokens_per_second; do
        printf "| %-16s | %-8s | %7ss | %10s |\n" "$model" "$category" "$avg_time" "$tokens_per_second"
    done
    
    echo "-------------------------------------------------------"
    
    return 0
}

# Function to run a comprehensive benchmark across all categories
run_comprehensive_benchmark() {
    log_info "Running comprehensive benchmark across all categories..."
    
    # Parameters
    local max_tokens="${1:-200}"
    local temperature="${2:-0.7}"
    local repetitions="${3:-2}"
    
    # Create reports directory if it doesn't exist
    mkdir -p "$REPORT_DIR"
    
    # Generate report filename with timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local report_file="$REPORT_DIR/comprehensive-benchmark-$timestamp.csv"
    
    # Create CSV header
    echo "Model,Category,AvgTime(s),AvgTokens,TokensPerSecond" > "$report_file"
    
    # Get available categories
    local categories=("${!TEST_PROMPTS[@]}")
    
    # For each category, run benchmark
    for category in "${categories[@]}"; do
        log_info "Benchmarking category: $category"
        
        # Run benchmark for this category
        compare_models "$category" "$max_tokens" "$temperature" "$repetitions" >> "$report_file"
        
        log_info "Completed benchmark for category: $category"
    done
    
    log_info "✅ Comprehensive benchmark complete"
    log_info "Results saved to: $report_file"
    
    # Generate report
    generate_benchmark_report "$report_file"
    
    return 0
}

# Function to generate a benchmark report
generate_benchmark_report() {
    local csv_file="$1"
    local html_file="${csv_file%.csv}.html"
    
    log_info "Generating benchmark report..."
    
    # Check if CSV file exists
    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV file not found: $csv_file"
        return 1
    fi
    
    # Create HTML report
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MCP Stack Model Benchmark Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1, h2, h3 {
            color: #2c3e50;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 10px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
            font-weight: bold;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        .highlight {
            background-color: #e3f2fd;
            font-weight: bold;
        }
        .chart-container {
            width: 100%;
            max-width: 1000px;
            height: 400px;
            margin: 20px 0;
        }
        .category-section {
            margin-bottom: 40px;
            border: 1px solid #eee;
            padding: 20px;
            border-radius: 5px;
        }
        .timestamp {
            color: #666;
            font-style: italic;
            margin-bottom: 20px;
        }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.7.1/dist/chart.min.js"></script>
</head>
<body>
    <div class="container">
        <h1>MCP Stack Model Benchmark Report</h1>
        <p class="timestamp">Generated on: $(date)</p>
        
        <h2>Overview</h2>
        <p>This report shows the performance comparison of different models across various categories.</p>
        
        <div class="chart-container">
            <canvas id="performanceChart"></canvas>
        </div>
        
        <h2>Results by Category</h2>
EOF
    
    # Process CSV data
    local categories=$(tail -n +2 "$csv_file" | cut -d, -f2 | sort | uniq)
    
    # For each category, create a section in the HTML
    for category in $categories; do
        cat >> "$html_file" << EOF
        <div class="category-section">
            <h3>Category: $category</h3>
            <table>
                <thead>
                    <tr>
                        <th>Model</th>
                        <th>Average Time (s)</th>
                        <th>Average Tokens</th>
                        <th>Tokens per Second</th>
                    </tr>
                </thead>
                <tbody>
EOF
        
        # Extract data for this category and sort by tokens per second (fastest first)
        grep ",$category," "$csv_file" | sort -t, -k5,5nr | while IFS=, read -r model cat avg_time avg_tokens tokens_per_second; do
            # Skip header
            if [[ "$model" == "Model" ]]; then
                continue
            fi
            
            cat >> "$html_file" << EOF
                    <tr>
                        <td>$model</td>
                        <td>$avg_time</td>
                        <td>$avg_tokens</td>
                        <td>$tokens_per_second</td>
                    </tr>
EOF
        done
        
        cat >> "$html_file" << EOF
                </tbody>
            </table>
        </div>
EOF
    done
    
    # Add JavaScript for charts
    cat >> "$html_file" << EOF
        <h2>System Information</h2>
        <table>
            <tr>
                <th>Hardware/Software</th>
                <th>Details</th>
            </tr>
            <tr>
                <td>Operating System</td>
                <td>$(uname -s)</td>
            </tr>
            <tr>
                <td>CPU</td>
                <td>$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//' || echo "Unknown")</td>
            </tr>
            <tr>
                <td>CPU Cores</td>
                <td>$(nproc 2>/dev/null || echo "Unknown")</td>
            </tr>
            <tr>
                <td>Memory</td>
                <td>$(free -h | grep Mem | awk '{print $2}' 2>/dev/null || echo "Unknown")</td>
            </tr>
            <tr>
                <td>GPU</td>
                <td>$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "None/Unknown")</td>
            </tr>
            <tr>
                <td>Docker Version</td>
                <td>$(docker --version 2>/dev/null || echo "Unknown")</td>
            </tr>
        </table>
        
        <script>
            // Prepare data for charts
            const categories = [];
            const models = [];
            const tokensByModel = {};
            const timesByModel = {};
            
            // Parse CSV data
            const csvData = \`$(cat "$csv_file")\`;
            const rows = csvData.split('\\n').filter(row => row.trim());
            
            // Skip header row
            for (let i = 1; i < rows.length; i++) {
                if (!rows[i]) continue;
                const [model, category, avgTime, avgTokens, tokensPerSec] = rows[i].split(',');
                
                if (!categories.includes(category)) {
                    categories.push(category);
                }
                
                if (!models.includes(model)) {
                    models.push(model);
                    tokensByModel[model] = {};
                    timesByModel[model] = {};
                }
                
                tokensByModel[model][category] = parseFloat(tokensPerSec);
                timesByModel[model][category] = parseFloat(avgTime);
            }
            
            // Prepare dataset for the chart
            const datasets = models.map((model, index) => {
                // Generate a color based on index
                const hue = (index * 137) % 360;
                const color = \`hsl(\${hue}, 70%, 60%)\`;
                
                return {
                    label: model,
                    data: categories.map(category => tokensByModel[model][category] || 0),
                    backgroundColor: color,
                    borderColor: color,
                    borderWidth: 1
                };
            });
            
            // Create performance chart
            const ctx = document.getElementById('performanceChart').getContext('2d');
            new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: categories,
                    datasets: datasets
                },
                options: {
                    responsive: true,
                    plugins: {
                        title: {
                            display: true,
                            text: 'Tokens per Second by Model and Category',
                            font: {
                                size: 16
                            }
                        },
                        legend: {
                            position: 'top',
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            title: {
                                display: true,
                                text: 'Tokens per Second'
                            }
                        },
                        x: {
                            title: {
                                display: true,
                                text: 'Category'
                            }
                        }
                    }
                }
            });
        </script>
    </div>
</body>
</html>
EOF
    
    log_info "✅ Benchmark report generated: $html_file"
    
    # Open the report if xdg-open is available
    if command -v xdg-open &> /dev/null; then
        xdg-open "$html_file" &
    elif command -v open &> /dev/null; then
        open "$html_file" &
    else
        log_info "To view the report, open: $html_file"
    fi
    
    return 0
}

# Function to benchmark a custom prompt
benchmark_custom_prompt() {
    local prompt="$1"
    local max_tokens="${2:-200}"
    local temperature="${3:-0.7}"
    local repetitions="${4:-3}"
    
    log_info "Benchmarking custom prompt: \"$prompt\""
    
    # Create a temporary category
    TEST_PROMPTS["custom"]="$prompt"
    
    # Run benchmark with custom category
    compare_models "custom" "$max_tokens" "$temperature" "$repetitions"
    
    return 0
}

# Print usage
print_usage() {
    cat << EOF
Benchmark Utilities for Docker MCP Stack

Usage: $0 <command> [options]

Commands:
  model <model> <port> [category] [max_tokens] [temperature] [repetitions]
                                Benchmark a specific model
  compare [category] [max_tokens] [temperature] [repetitions]
                                Compare all running models
  comprehensive [max_tokens] [temperature] [repetitions]
                                Run comprehensive benchmark across all categories
  custom <prompt> [max_tokens] [temperature] [repetitions]
                                Benchmark with a custom prompt
  help                         Show this help message

Categories:
  general                      Basic AI understanding
  reasoning                    Logical reasoning and problem solving
  knowledge                    Factual knowledge
  creativity                   Creative writing
  code                         Code generation
  instruction                  Following instructions

Examples:
  $0 model smollm2 12434 reasoning 200 0.7 3
  $0 compare code 300
  $0 comprehensive 200 0.7 2
  $0 custom "Explain how neural networks work" 300 0.7 3

Notes:
  - Default max_tokens: 200
  - Default temperature: 0.7
  - Default repetitions: 3 for model/compare, 2 for comprehensive
EOF
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        return 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        model)
            if [[ $# -lt 2 ]]; then
                log_error "Missing model name or port"
                print_usage
                return 1
            fi
            local model="$1"
            local port="$2"
            local category="${3:-general}"
            local max_tokens="${4:-200}"
            local temperature="${5:-0.7}"
            local repetitions="${6:-3}"
            
            benchmark_model "$model" "$port" "$category" "$max_tokens" "$temperature" "$repetitions"
            ;;
        compare)
            local category="${1:-general}"
            local max_tokens="${2:-200}"
            local temperature="${3:-0.7}"
            local repetitions="${4:-3}"
            
            compare_models "$category" "$max_tokens" "$temperature" "$repetitions"
            ;;
        comprehensive)
            local max_tokens="${1:-200}"
            local temperature="${2:-0.7}"
            local repetitions="${3:-2}"
            
            run_comprehensive_benchmark "$max_tokens" "$temperature" "$repetitions"
            ;;
        custom)
            if [[ $# -lt 1 ]]; then
                log_error "Missing custom prompt"
                print_usage
                return 1
            fi
            local prompt="$1"
            local max_tokens="${2:-200}"
            local temperature="${3:-0.7}"
            local repetitions="${4:-3}"
            
            benchmark_custom_prompt "$prompt" "$max_tokens" "$temperature" "$repetitions"
            ;;
        help)
            print_usage
            ;;
        *)
            log_error "Unknown command: $command"
            print_usage
            return 1
            ;;
    esac
}

# Execute main function if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
