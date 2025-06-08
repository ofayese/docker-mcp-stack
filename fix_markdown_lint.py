#!/usr/bin/env python3
"""
Script to fix markdownlint errors in the Docker MCP Stack project.
"""

import re
import os

def fix_line_length(content, max_length=120):
    """Fix line length issues by breaking long lines appropriately."""
    lines = content.split('\n')
    fixed_lines = []
    
    for line in lines:
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
                    break_points = ['. ', ', ', ' - ', ' and ', ' or ']
                    best_break = -1
                    
                    for bp in break_points:
                        pos = rest.rfind(bp, 0, max_length - len(prefix))
                        if pos > best_break:
                            best_break = pos + len(bp)
                    
                    if best_break > 0:
                        fixed_lines.append(prefix + rest[:best_break].rstrip())
                        # Continue with remaining text on new line with proper indentation
                        remaining = rest[best_break:].lstrip()
                        if remaining:
                            fixed_lines.append(' ' * (indent + 2) + remaining)
                    else:
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
                        fixed_lines.append(line)
                else:
                    fixed_lines.append(line)
    
    return '\n'.join(fixed_lines)

def fix_fenced_code_blocks(content):
    """Add language specification to fenced code blocks."""
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
                if next_line.startswith('docker ') or next_line.startswith('docker-compose'):
                    fixed_lines.append('```bash')
                elif next_line.startswith('npm ') or next_line.startswith('node '):
                    fixed_lines.append('```bash')
                elif next_line.startswith('git ') or next_line.startswith('cd '):
                    fixed_lines.append('```bash')
                elif next_line.startswith('make '):
                    fixed_lines.append('```bash')
                elif 'version:' in next_line or 'services:' in next_line:
                    fixed_lines.append('```yaml')
                elif next_line.startswith('{') or next_line.startswith('['):
                    fixed_lines.append('```json')
                elif 'def ' in next_line or 'import ' in next_line:
                    fixed_lines.append('```python')
                elif 'function ' in next_line or 'const ' in next_line:
                    fixed_lines.append('```javascript')
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
    """Fix ordered list prefix issues."""
    lines = content.split('\n')
    fixed_lines = []
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Check if this is an ordered list item
        ol_match = re.match(r'^(\s*)(\d+)\.\s', line)
        if ol_match:
            indent = ol_match.group(1)
            current_num = int(ol_match.group(2))
            
            # Look for the previous list item to determine correct numbering
            prev_num = 0
            for j in range(i - 1, -1, -1):
                prev_line = lines[j]
                prev_ol_match = re.match(r'^(\s*)(\d+)\.\s', prev_line)
                if prev_ol_match and prev_ol_match.group(1) == indent:
                    prev_num = int(prev_ol_match.group(2))
                    break
                elif prev_line.strip() == '':
                    continue
                else:
                    break
            
            # Fix the numbering
            correct_num = prev_num + 1
            if current_num != correct_num:
                fixed_line = line.replace(f'{current_num}.', f'{correct_num}.', 1)
                fixed_lines.append(fixed_line)
            else:
                fixed_lines.append(line)
        else:
            fixed_lines.append(line)
        i += 1
    
    return '\n'.join(fixed_lines)

def fix_markdown_file(filepath):
    """Fix markdown linting issues in a single file."""
    print(f"Fixing {filepath}...")
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Apply fixes
    content = fix_fenced_code_blocks(content)
    content = fix_ordered_list_prefixes(content)
    content = fix_line_length(content)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"Fixed {filepath}")

def main():
    """Main function to fix all markdown files with issues."""
    files_to_fix = [
        'CONTRIBUTING.md',
        'docs/api-reference.md',
        'docs/backup-recovery.md',
        'FINAL_ASSESSMENT.md',
        'README.md'
    ]
    
    base_path = r'e:\data\docker-mcp-stack'
    
    for file in files_to_fix:
        filepath = os.path.join(base_path, file)
        if os.path.exists(filepath):
            fix_markdown_file(filepath)
        else:
            print(f"File not found: {filepath}")

if __name__ == "__main__":
    main()
