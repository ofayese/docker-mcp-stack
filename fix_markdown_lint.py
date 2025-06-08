#!/usr/bin/env python3
"""
Script to fix markdownlint errors in the Docker MCP Stack project.

This enhanced script addresses common markdown linting issues including:
- Line length (MD013)
- Code fence language specification (MD048)
- Ordered list numbering (MD029)
- Heading consistency (MD003)
- List indent consistency (MD007)
- Trailing whitespace (MD009)
- Blank lines around headings, lists and code blocks (MD022, MD023)
"""

import re
import os
import sys
import argparse
import logging
import json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path


# Configure logger
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('markdown_lint_fixer')


def load_markdownlint_config(config_path='.markdownlint.json'):
    """
    Load markdownlint configuration file to respect project-specific rules.
    
    Args:
        config_path (str): Path to the markdownlint configuration file
        
    Returns:
        dict: Configuration settings, or defaults if file not found
    """
    default_config = {
        "line_length": 120,
        "heading_style": "atx",
        "list_indent": 2
    }
    
    try:
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                
            # Extract relevant settings
            result = {}
            result["line_length"] = config.get("MD013", {}).get(
                "line_length", 120)
            
            heading_style = config.get("MD003", {}).get("style", "atx")
            result["heading_style"] = heading_style
            
            list_indent = config.get("MD007", {}).get("indent", 2)
            result["list_indent"] = list_indent
            
            return result
        else:
            logger.warning(
                f"Markdownlint config not found at {config_path}, using defaults")
            return default_config
    except Exception as e:
        logger.error(f"Error loading markdownlint config: {str(e)}")
        return default_config


def fix_line_length(content, max_length=120):
    """
    Fix line length issues by breaking long lines appropriately.
    
    Args:
        content (str): The markdown content to fix
        max_length (int): Maximum line length
        
    Returns:
        str: Fixed content with proper line lengths
    """
    lines = content.split('\n')
    fixed_lines = []
    in_code_block = False
    
    for line in lines:
        # Skip code blocks as they're exempt from line length rules
        if line.strip().startswith('```'):
            in_code_block = not in_code_block
            fixed_lines.append(line)
            continue
        
        if in_code_block:
            fixed_lines.append(line)
            continue
            
        # Skip headings, they shouldn't be broken
        if line.strip().startswith('#'):
            fixed_lines.append(line)
            continue
            
        if len(line) <= max_length:
            fixed_lines.append(line)
        else:
            # Handle different types of long lines
            if line.strip().startswith('- ') or line.strip().startswith('* '):
                # List item - break after reasonable points
                indent = len(line) - len(line.lstrip())
                prefix = line[:indent + 2]  # Include indent and list marker
                rest = line[indent + 2:]
                
                if len(rest) > max_length - len(prefix):
                    # Try to break at sentence boundaries or commas
                    break_points = [
                        '. ', ', ', ': ', '; ', ' - ', ' and ', ' or ', ' but ']
                    best_break = -1
                    
                    for bp in break_points:
                        pos = rest.rfind(bp, 0, max_length - len(prefix))
                        if pos > best_break:
                            best_break = (
                                pos + len(bp) - 1 if bp.endswith(' ')
                                else pos + len(bp))
                    
                    # If no good break point found, try breaking at a word
                    # boundary
                    if best_break <= 0:
                        words = rest.split()
                        current_len = 0
                        for i, word in enumerate(words):
                            if (current_len + len(word) + 1 >
                                    max_length - len(prefix)):
                                if i > 0:  # We have at least one word
                                    best_break = current_len
                                break
                            current_len += len(word) + 1  # +1 for the space
                    
                    if best_break > 0:
                        fixed_lines.append(prefix + rest[:best_break].rstrip())
                        # Continue with remaining text on new line with proper
                        # indentation
                        remaining = rest[best_break:].lstrip()
                        if remaining:
                            fixed_lines.append(' ' * (indent + 2) + remaining)
                    else:
                        # If we can't find a good break point, keep the line as is
                        fixed_lines.append(line)
                else:
                    fixed_lines.append(line)
            else:
                # For other long lines, try to break at natural points
                if '](http' in line:
                    # Markdown link - try to break before the link
                    match = re.search(r'\[([^\]]+)\]\(http[^)]+\)', line)
                    if match and match.start() < max_length:
                        before = line[:match.start()].rstrip()
                        link_part = line[match.start():]
                        if before:
                            fixed_lines.append(before)
                            fixed_lines.append(link_part)
                        else:
                            fixed_lines.append(line)
                    else:
                        # Try to break at other points
                        break_points = [
                            '. ', ', ', ': ', '; ', ' - ', ' and ', ' or ', ' but ']
                        best_break = -1
                        
                        for bp in break_points:
                            pos = line.rfind(bp, 0, max_length)
                            if pos > best_break:
                                best_break = (
                                    pos + len(bp) - 1 if bp.endswith(' ')
                                    else pos + len(bp))
                        
                        if best_break > 0:
                            fixed_lines.append(line[:best_break].rstrip())
                            remaining = line[best_break:].lstrip()
                            if remaining:
                                # Check indentation level for continuation
                                indent = len(line) - len(
                                    line.lstrip())
                                fixed_lines.append(' ' * indent + remaining)
                        else:
                            fixed_lines.append(line)
                else:
                    # Try to break at punctuation or conjunctions
                    break_points = [
                        '. ', ', ', ': ', '; ', ' - ', ' and ', ' or ', ' but ']
                    best_break = -1
                    
                    for bp in break_points:
                        pos = line.rfind(bp, 0, max_length)
                        if pos > best_break:
                            best_break = (
                                pos + len(bp) - 1 if bp.endswith(' ')
                                else pos + len(bp))
                    
                    if best_break > 0:
                        fixed_lines.append(line[:best_break].rstrip())
                        remaining = line[best_break:].lstrip()
                        if remaining:
                            # Check indentation level for continuation
                            indent = len(line) - len(
                                line.lstrip())
                            fixed_lines.append(' ' * indent + remaining)
                    else:
                        # If no good break point, try to break at a word boundary
                        words = line.split()
                        if len(words) > 1:
                            current_len = 0
                            indent = len(line) - len(line.lstrip())
                            current_line = ' ' * indent
                            
                            for word in words:
                                if (current_len + len(word) + 1 >
                                        max_length):
                                    fixed_lines.append(current_line.rstrip())
                                    current_line = ' ' * indent + word + ' '
                                    current_len = len(current_line)
                                else:
                                    current_line += word + ' '
                                    current_len += len(word) + 1
                            
                            if current_line.strip():
                                fixed_lines.append(current_line.rstrip())
                        else:
                            # Single long word, can't break nicely
                            fixed_lines.append(line)
    
    return '\n'.join(fixed_lines)


def fix_fenced_code_blocks(content):
    """
    Add language specification to fenced code blocks.
    
    Args:
        content (str): The markdown content to fix
        
    Returns:
        str: Fixed content with language-specified code blocks
    """
    # Pattern to find fenced code blocks without language
    pattern = r'^```\s*$'
    lines = content.split('\n')
    fixed_lines = []
    
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(pattern, line):
            # Look ahead to determine the appropriate language
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                
                # Determine language based on content
                if (next_line.startswith('docker ') or 
                        next_line.startswith('docker-compose')):
                    fixed_lines.append('```bash')
                elif (next_line.startswith('npm ') or 
                      next_line.startswith('node ')):
                    fixed_lines.append('```bash')
                elif (next_line.startswith('git ') or 
                      next_line.startswith('cd ')):
                    fixed_lines.append('```bash')
                elif (next_line.startswith('make ') or 
                      next_line.startswith('sudo ')):
                    fixed_lines.append('```bash')
                elif (next_line.startswith('curl ') or 
                      next_line.startswith('wget ')):
                    fixed_lines.append('```bash')
                elif ('version:' in next_line or 
                      'services:' in next_line):
                    fixed_lines.append('```yaml')
                elif (next_line.startswith('{') or 
                      next_line.startswith('[')):
                    fixed_lines.append('```json')
                elif (next_line.startswith('<') and 
                      ('>' in next_line)):
                    fixed_lines.append('```html')
                elif ('def ' in next_line or 
                      'import ' in next_line or 
                      next_line.startswith('class ')):
                    fixed_lines.append('```python')
                elif ('function ' in next_line or 
                      'const ' in next_line or 
                      'var ' in next_line or 
                      'let ' in next_line):
                    fixed_lines.append('```javascript')
                elif ('SELECT ' in next_line.upper() or 
                      'CREATE TABLE' in next_line.upper()):
                    fixed_lines.append('```sql')
                elif ('#!/bin/bash' in next_line or 
                      '#!/usr/bin/env bash' in next_line):
                    fixed_lines.append('```bash')
                elif '#!/usr/bin/env python' in next_line:
                    fixed_lines.append('```python')
                elif ('#include ' in next_line or 
                      'int main' in next_line):
                    fixed_lines.append('```c')
                else:
                    # Default to bash for shell commands
                    fixed_lines.append('```bash')
            else:
                fixed_lines.append('```bash')
        else:
            fixed_lines.append(line)
        i += 1
    
    return '\n'.join(fixed_lines)


def fix_ordered_list_prefixes(content):
    """
    Fix ordered list prefix issues.
    
    Args:
        content (str): The markdown content to fix
        
    Returns:
        str: Fixed content with correct ordered list numbering
    """
    lines = content.split('\n')
    fixed_lines = []
    
    # Track list items at different indentation levels
    list_counters = {}
    in_code_block = False
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Skip modifying code blocks
        if line.strip().startswith('```'):
            in_code_block = not in_code_block
            fixed_lines.append(line)
            i += 1
            continue
        
        if in_code_block:
            fixed_lines.append(line)
            i += 1
            continue
        
        # Check if this is an ordered list item
        ol_match = re.match(r'^(\s*)(\d+)\.\s(.*)$', line)
        if ol_match:
            indent = ol_match.group(1)
            current_num = int(ol_match.group(2))
            content = ol_match.group(3)
            
            # Reset counter if this is a new list
            if (i == 0 or lines[i-1].strip() == '' or 
                    not re.match(r'^\s*\d+\.\s', lines[i-1])):
                list_counters[indent] = 1
            
            # Get the correct number for this item
            correct_num = list_counters.get(indent, 1)
            
            # Update the counter for next item at this indentation level
            list_counters[indent] = correct_num + 1
            
            # Fix the numbering if needed
            if current_num != correct_num:
                fixed_lines.append(f"{indent}{correct_num}. {content}")
            else:
                fixed_lines.append(line)
        else:
            fixed_lines.append(line)
            
            # If we hit a blank line, we might be ending a list at some levels
            if line.strip() == '':
                # Find all indentation levels greater than or equal to the next non-blank line
                next_indent = ''
                for j in range(i + 1, len(lines)):
                    if lines[j].strip() != '':
                        next_indent = len(lines[j]) - len(lines[j].lstrip())
                        break
                
                # Reset counters for all indentation levels greater than the next non-blank line
                # This handles the case where a new list starts after a blank line
                keys_to_remove = []
                for indent in list_counters:
                    # Compare lengths of strings, not string to int
                    if isinstance(next_indent, int):
                        if len(indent) >= next_indent:
                            keys_to_remove.append(indent)
                    else:
                        if len(indent) >= len(next_indent):
                            keys_to_remove.append(indent)
                
                for key in keys_to_remove:
                    del list_counters[key]
                    
        i += 1
    
    return '\n'.join(fixed_lines)


def fix_trailing_whitespace(content):
    """
    Remove trailing whitespace from lines (MD009).
    
    Args:
        content (str): The markdown content to fix
        
    Returns:
        str: Fixed content with trailing whitespace removed
    """
    lines = content.split('\n')
    fixed_lines = []
    
    for line in lines:
        fixed_lines.append(line.rstrip())
    
    return '\n'.join(fixed_lines)


def fix_blank_lines(content):
    """
    Ensure proper blank lines around elements (MD022, MD023, etc.)
    
    Args:
        content (str): The markdown content to fix
        
    Returns:
        str: Fixed content with proper blank lines
    """
    lines = content.split('\n')
    fixed_lines = []
    in_code_block = False
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Handle code blocks
        if line.strip().startswith('```'):
            in_code_block = not in_code_block
            
            # Add blank line before code block if needed
            if not in_code_block:  # End of code block
                fixed_lines.append(line)
                if (i + 1 < len(lines) and 
                        lines[i + 1].strip() != '' and 
                        not lines[i + 1].strip().startswith('#')):
                    fixed_lines.append('')
            else:  # Start of code block
                if i > 0 and fixed_lines and fixed_lines[-1].strip() != '':
                    fixed_lines.append('')
                fixed_lines.append(line)
        elif in_code_block:
            fixed_lines.append(line)
        # Handle headings - ensure blank line before and after
        elif line.strip().startswith('#'):
            # Add blank line before heading if needed
            if i > 0 and fixed_lines and fixed_lines[-1].strip() != '':
                fixed_lines.append('')
            fixed_lines.append(line)
            # Add blank line after heading if needed
            if i + 1 < len(lines) and lines[i + 1].strip() != '':
                fixed_lines.append('')
        # Handle list items
        elif (re.match(r'^\s*[-*+]\s', line) or 
              re.match(r'^\s*\d+\.\s', line)):
            # For list items, we don't add blank lines between items
            # But we do add a blank line before a list starts
            if i > 0 and fixed_lines:
                prev_line = fixed_lines[-1].strip()
                is_prev_list = (re.match(r'^\s*[-*+]\s', prev_line) or 
                                re.match(r'^\s*\d+\.\s', prev_line))
                if prev_line != '' and not is_prev_list:
                    fixed_lines.append('')
            fixed_lines.append(line)
        else:
            fixed_lines.append(line)
        
        i += 1
    
    # Clean up multiple blank lines
    cleaned_lines = []
    prev_blank = False
    for line in fixed_lines:
        if line.strip() == '':
            if not prev_blank:
                cleaned_lines.append(line)
            prev_blank = True
        else:
            cleaned_lines.append(line)
            prev_blank = False
    
    return '\n'.join(cleaned_lines)


def fix_list_indent_consistency(content, indent=2):
    """
    Ensure list indentation is consistent (MD007).
    
    Args:
        content (str): The markdown content to fix
        indent (int): The number of spaces to use for list indentation
        
    Returns:
        str: Fixed content with consistent list indentation
    """
    lines = content.split('\n')
    fixed_lines = []
    in_code_block = False
    
    for line in lines:
        if line.strip().startswith('```'):
            in_code_block = not in_code_block
            fixed_lines.append(line)
            continue
            
        if in_code_block:
            fixed_lines.append(line)
            continue
            
        # Check for list items
        list_match = re.match(r'^(\s*)[-*+]\s', line)
        if list_match:
            leading_space = list_match.group(1)
            # Calculate the list level (how nested is this list item)
            level = len(leading_space) // indent
            if level == 0:
                # Top level list item, no indentation needed
                fixed_line = re.sub(r'^\s*', '', line, 1)
                fixed_lines.append(fixed_line)
            else:
                # Nested list item, ensure proper indentation
                correct_indent = ' ' * (level * indent)
                fixed_line = re.sub(r'^\s*', correct_indent, line, 1)
                fixed_lines.append(fixed_line)
        else:
            fixed_lines.append(line)
    
    return '\n'.join(fixed_lines)


def fix_heading_style(content, style='atx'):
    """
    Ensure heading style is consistent (MD003).
    
    Args:
        content (str): The markdown content to fix
        style (str): The heading style to use ('atx' or 'setext')
        
    Returns:
        str: Fixed content with consistent heading style
    """
    lines = content.split('\n')
    fixed_lines = []
    in_code_block = False
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        if line.strip().startswith('```'):
            in_code_block = not in_code_block
            fixed_lines.append(line)
            i += 1
            continue
            
        if in_code_block:
            fixed_lines.append(line)
            i += 1
            continue
        
        # Check for setext-style headings (underlining with === or ---)
        if i < len(lines) - 1:
            next_line = lines[i + 1]
            if (next_line.strip() and 
                    (all(c == '=' for c in next_line.strip()) or 
                     all(c == '-' for c in next_line.strip()))):
                if style == 'atx':
                    # Convert to ATX style
                    level = 1 if '=' in next_line else 2
                    fixed_lines.append('#' * level + ' ' + line.strip())
                    i += 2  # Skip the underline
                    continue
                else:
                    # Keep setext style
                    fixed_lines.append(line)
                    fixed_lines.append(next_line)
                    i += 2
                    continue
        
        # Check for ATX-style headings
        atx_match = re.match(r'^(#+)\s+(.+?)(\s+#+)?$', line)
        if atx_match:
            if style == 'atx':
                # Normalize ATX style (remove closing #s)
                level = len(atx_match.group(1))
                heading_text = atx_match.group(2).strip()
                fixed_lines.append('#' * level + ' ' + heading_text)
            else:
                # Convert to setext style (only for level 1 and 2)
                level = len(atx_match.group(1))
                heading_text = atx_match.group(2).strip()
                if level <= 2:
                    fixed_lines.append(heading_text)
                    fixed_lines.append(
                        '=' if level == 1 else '-' * len(heading_text))
                else:
                    # Can't convert level 3+ to setext, keep as ATX
                    fixed_lines.append('#' * level + ' ' + heading_text)
        else:
            fixed_lines.append(line)
        
        i += 1
    
    return '\n'.join(fixed_lines)


def fix_markdown_file(filepath, config, dry_run=False, fixes=None):
    """
    Fix markdown linting issues in a single file.
    
    Args:
        filepath (str): Path to the markdown file to fix
        config (dict): Configuration settings from markdownlint
        dry_run (bool): If True, don't write changes to the file
        fixes (list): List of fixes to apply, or None for all fixes
        
    Returns:
        bool: True if changes were made, False otherwise
    """
    logger.info(f"Processing {filepath}...")
    
    if fixes is None or 'all' in fixes:
        apply_all = True
    else:
        apply_all = False
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            original_content = f.read()
        
        # Apply fixes
        content = original_content
        
        if apply_all or 'whitespace' in fixes:
            content = fix_trailing_whitespace(content)
            
        if apply_all or 'code-blocks' in fixes:
            content = fix_fenced_code_blocks(content)
            
        if apply_all or 'lists' in fixes:
            content = fix_ordered_list_prefixes(content)
            content = fix_list_indent_consistency(
                content, config.get('list_indent', 2))
            
        if apply_all or 'headings' in fixes:
            content = fix_heading_style(
                content, config.get('heading_style', 'atx'))
            
        if apply_all or 'blank-lines' in fixes:
            content = fix_blank_lines(content)
            
        if apply_all or 'line-length' in fixes:
            content = fix_line_length(content, config.get('line_length', 120))
        
        # Check if content changed
        if content != original_content:
            if not dry_run:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
                logger.info(f"Fixed {filepath}")
            else:
                logger.info(f"[DRY RUN] Would fix {filepath}")
            return True
        else:
            logger.info(f"No changes needed for {filepath}")
            return False
    except Exception as e:
        logger.error(f"Error processing {filepath}: {str(e)}")
        return False


def find_markdown_files(directory, patterns=None):
    """
    Find all markdown files in the directory that match the patterns.
    
    Args:
        directory (str): Base directory to search in
        patterns (list): List of glob patterns to match files against
        
    Returns:
        list: List of matched file paths
    """
    if patterns is None:
        patterns = ['**/*.md']
        
    matched_files = []
    base_path = Path(directory)
    
    try:
        for pattern in patterns:
            for file_path in base_path.glob(pattern):
                if file_path.is_file():
                    matched_files.append(str(file_path))
    except Exception as e:
        logger.error(f"Error finding markdown files: {str(e)}")
        
    return matched_files


def parse_arguments():
    """
    Parse command line arguments.
    
    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description='Fix markdownlint errors in Markdown files.')
    
    parser.add_argument(
        '-f', '--files',
        nargs='+',
        help='Specific markdown files to process'
    )
    
    parser.add_argument(
        '-d', '--directory',
        default='.',
        help='Directory to scan for markdown files (default: current directory)'
    )
    
    parser.add_argument(
        '-p', '--pattern',
        nargs='+',
        default=['**/*.md'],
        help='Glob patterns to match markdown files (default: **/*.md)'
    )
    
    parser.add_argument(
        '--config',
        default='.markdownlint.json',
        help='Path to markdownlint config file (default: .markdownlint.json)'
    )
    
    parser.add_argument(
        '--line-length',
        type=int,
        help='Override maximum line length'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be fixed without making changes'
    )
    
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    parser.add_argument(
        '--parallel',
        action='store_true',
        help='Process files in parallel for better performance'
    )
    
    parser.add_argument(
        '--fix',
        nargs='+',
        choices=[
            'line-length', 
            'code-blocks', 
            'lists', 
            'headings', 
            'whitespace', 
            'blank-lines', 
            'all'
        ],
        default=['all'],
        help='Specify which fixes to apply (default: all)'
    )
    
    return parser.parse_args()


def main():
    """Main function to fix all markdown files with issues."""
    args = parse_arguments()
    
    # Configure logging level
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Load markdownlint configuration
    config = load_markdownlint_config(args.config)
    
    # Override configuration with command line arguments
    if args.line_length:
        config['line_length'] = args.line_length
    
    # List of files to process
    files_to_process = []
    
    if args.files:
        # Process specific files
        for file_path in args.files:
            if os.path.exists(file_path):
                files_to_process.append(file_path)
            else:
                logger.warning(f"File not found: {file_path}")
    else:
        # Use default files or scan directory
        base_path = args.directory
        
        if os.path.exists(base_path):
            files_to_process = find_markdown_files(base_path, args.pattern)
            if not files_to_process:
                logger.warning(
                    f"No markdown files found in {base_path} "
                    f"matching patterns: {args.pattern}")
        else:
            logger.error(f"Directory not found: {base_path}")
            return 1
    
    if not files_to_process:
        logger.error("No files to process.")
        return 1
    
    logger.info(f"Found {len(files_to_process)} markdown files to process")
    
    # Process files
    fixed_count = 0
    
    if args.parallel and len(files_to_process) > 1:
        # Process files in parallel
        with ProcessPoolExecutor() as executor:
            futures = [
                executor.submit(
                    fix_markdown_file, 
                    file_path, 
                    config, 
                    args.dry_run,
                    args.fix
                )
                for file_path in files_to_process
            ]
            
            for future in futures:
                if future.result():
                    fixed_count += 1
    else:
        # Process files sequentially
        for file_path in files_to_process:
            if fix_markdown_file(file_path, config, args.dry_run, args.fix):
                fixed_count += 1
    
    if args.dry_run:
        logger.info(
            f"[DRY RUN] Would fix {fixed_count} of {len(files_to_process)} files")
    else:
        logger.info(f"Fixed {fixed_count} of {len(files_to_process)} files")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
