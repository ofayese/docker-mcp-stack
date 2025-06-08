#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Markdown linting utility script for Docker MCP Stack
.DESCRIPTION
    This script provides various markdown linting operations including checking,
    fixing, and reporting on markdown files in the project.
.PARAMETER Action
    The action to perform: check, fix, report, or install
.PARAMETER Path
    Specific path to lint (optional, defaults to all markdown files)
.EXAMPLE
    .\scripts\lint-docs.ps1 -Action check
    .\scripts\lint-docs.ps1 -Action fix -Path "README.md"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("check", "fix", "report", "install", "help")]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [string]$Path = "**/*.md"
)

# Color functions for better output
function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Info-Custom {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Test-MarkdownlintInstalled {
    try {
        $null = Get-Command markdownlint -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Install-Dependencies {
    Write-Info-Custom "Installing markdownlint dependencies..."
    
    if (-not (Test-Path "package.json")) {
        Write-Error-Custom "package.json not found. Please ensure you're in the project root directory."
        exit 1
    }
    
    try {
        npm install
        Write-Success "Dependencies installed successfully!"
    }
    catch {
        Write-Error-Custom "Failed to install dependencies: $_"
        exit 1
    }
}

function Invoke-MarkdownLint {
    param(
        [string]$LintPath,
        [bool]$Fix = $false
    )
    
    if (-not (Test-MarkdownlintInstalled)) {
        Write-Warning-Custom "markdownlint not found. Installing dependencies first..."
        Install-Dependencies
    }
    
    $arguments = @()
    $arguments += "--config"
    $arguments += ".markdownlint.json"
    
    if ($Fix) {
        $arguments += "--fix"
    }
    
    $arguments += $LintPath
    
    try {
        & markdownlint @arguments
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Error-Custom "Failed to run markdownlint: $_"
        return $false
    }
}

function Show-Help {
    Write-Host @"
Docker MCP Stack - Markdown Linting Utility

USAGE:
    .\scripts\lint-docs.ps1 -Action <action> [-Path <path>]

ACTIONS:
    check     - Check markdown files for linting issues
    fix       - Automatically fix markdown linting issues where possible
    report    - Generate a detailed linting report
    install   - Install markdownlint dependencies
    help      - Show this help message

EXAMPLES:
    .\scripts\lint-docs.ps1 -Action check
    .\scripts\lint-docs.ps1 -Action fix
    .\scripts\lint-docs.ps1 -Action check -Path "README.md"
    .\scripts\lint-docs.ps1 -Action fix -Path "docs/*.md"

CONFIGURATION:
    The linting rules are configured in .markdownlint.json
    Files to ignore are listed in .markdownlintignore
"@ -ForegroundColor Yellow
}

# Main script logic
switch ($Action) {
    "install" {
        Install-Dependencies
    }
    
    "check" {
        Write-Info-Custom "Checking markdown files: $Path"
        $success = Invoke-MarkdownLint -LintPath $Path
        
        if ($success) {
            Write-Success "All markdown files passed linting!"
        } else {
            Write-Error-Custom "Markdown linting found issues. Run with -Action fix to auto-fix where possible."
            exit 1
        }
    }
    
    "fix" {
        Write-Info-Custom "Fixing markdown files: $Path"
        $success = Invoke-MarkdownLint -LintPath $Path -Fix $true
        
        if ($success) {
            Write-Success "Markdown files have been fixed!"
        } else {
            Write-Warning-Custom "Some issues couldn't be automatically fixed. Please review manually."
        }
    }
    
    "report" {
        Write-Info-Custom "Generating markdown linting report..."
        
        # Get all markdown files
        $mdFiles = Get-ChildItem -Path . -Filter "*.md" -Recurse | Where-Object { $_.FullName -notmatch "node_modules|\.git" }
        
        Write-Host "`nMarkdown Files Found:" -ForegroundColor Yellow
        $mdFiles | ForEach-Object {
            Write-Host "  📄 $($_.FullName.Replace((Get-Location).Path, '.'))" -ForegroundColor White
        }
        
        Write-Host "`nRunning linting check..." -ForegroundColor Yellow
        Invoke-MarkdownLint -LintPath $Path
    }
    
    "help" {
        Show-Help
    }
    
    default {
        Write-Error-Custom "Unknown action: $Action"
        Show-Help
        exit 1
    }
}
