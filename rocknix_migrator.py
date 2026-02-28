#!/usr/bin/env python3
import os
import re
import argparse
import subprocess
import sys

# --- CONFIGURATION ---
# Extensions that are almost always safe to scan as text
TEXT_EXTENSIONS = {'.sh', '.bash', '.conf', '.service', '.c', '.cpp', '.py', '.go', '.mk', '.cmake', '.ac', '.in'}
# Extensions to strictly ignore (binaries, archives, images)
IGNORE_EXTENSIONS = {'.o', '.so', '.bin', '.exe', '.ko', '.a', '.img', '.tar', '.gz', '.zip', '.xz', '.png', '.jpg', '.dtb'}
# Patch files (Critical to detect, impossible to auto-convert)
PATCH_EXTENSIONS = {'.patch', '.diff'}

# Regex to find iptables commands
# Looks for "iptables" or "ip6tables" not preceded/followed by letters/numbers (avoiding matching "ip6tables-save" filenames etc in comments)
IPTABLES_REGEX = re.compile(r'(?<![a-zA-Z0-9_-])(sudo\s+)?(ip6?tables)(?![a-zA-Z0-9_-])\s+(.*)', re.MULTILINE)
# Regex to detect variables
VARIABLE_REGEX = re.compile(r'\$')

class Report:
    def __init__(self):
        self.simple = {}   
        self.complex = {}  

    def add_simple(self, filepath, line_num, original, converted):
        if filepath not in self.simple: self.simple[filepath] = []
        self.simple[filepath].append({'line': line_num, 'orig': original, 'conv': converted})

    def add_complex(self, filepath, line_num, original, reason):
        if filepath not in self.complex: self.complex[filepath] = []
        self.complex[filepath].append({'line': line_num, 'orig': original, 'reason': reason})

def is_text_file(filepath):
    """
    Reads the first 1024 bytes to check for binary NULL bytes.
    Also treats empty files as safe.
    """
    try:
        # Don't try to open broken symlinks or fifos
        if not os.path.isfile(filepath): 
            return False
            
        with open(filepath, 'rb') as f:
            chunk = f.read(1024)
            if b'\0' in chunk: 
                return False # Binary detected
            if not chunk: 
                return True # Empty file
            
            # Check if it decodes as UTF-8
            try:
                chunk.decode('utf-8')
            except UnicodeDecodeError:
                return False 
            return True
    except Exception:
        return False

def get_nft_translation(command):
    try:
        # Strip sudo, backslashes, and surrounding quotes if present
        clean_cmd = command.replace("sudo ", "").replace("\\", "").strip()
        
        # Invoke the system translator
        result = subprocess.run(['iptables-translate'] + clean_cmd.split(), 
                                capture_output=True, text=True, timeout=2)
        
        # Check if output is valid and not an error message
        if result.returncode == 0 and result.stdout.strip():
            out = result.stdout.strip()
            if "command not found" in out or "try `iptables -h`" in out:
                return None
            return out
    except Exception:
        return None
    return None

def scan_file(filepath, report, convert_mode):
    filename = os.path.basename(filepath)
    is_patch = filename.endswith(tuple(PATCH_EXTENSIONS))
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return

    file_modified = False
    new_lines = []

    for idx, line in enumerate(lines):
        line_stripped = line.strip()
        
        # Determine indentation for preservation
        indent = ""
        if line.startswith('\t'):
            indent = "\t"
        elif line.startswith(' '):
            indent = line[:len(line) - len(line.lstrip())]

        # Skip comments
        if line_stripped.startswith('#') and not "iptables" in line_stripped:
             # Heuristic: only skip comment if it doesn't look like commented out code we might want to see
            new_lines.append(line)
            continue

        match = IPTABLES_REGEX.search(line)
        if match:
            full_command = match.group(0).strip()
            
            # --- CLASSIFICATION ---

            # 1. Patch Files -> Complex
            if is_patch:
                report.add_complex(filepath, idx+1, full_command, "Inside Patch File")
                new_lines.append(line)
                continue

            # 2. Source Code -> Complex
            if filepath.endswith(('.c', '.cpp', '.go', '.py')):
                report.add_complex(filepath, idx+1, full_command, "Embedded in Source")
                new_lines.append(line)
                continue

            # 3. Variables -> Complex
            if VARIABLE_REGEX.search(full_command):
                reason = "Makefile Variable" if "$(" in full_command else "Shell Variable"
                report.add_complex(filepath, idx+1, full_command, reason)
                new_lines.append(line)
                continue

            # 4. Multi-line checks
            if line_stripped.endswith('\\'):
                report.add_complex(filepath, idx+1, full_command, "Multi-line Command")
                new_lines.append(line)
                continue

            # 5. Translation
            translated = get_nft_translation(full_command)
            
            if translated:
                report.add_simple(filepath, idx+1, full_command, translated)
                if convert_mode:
                    new_lines.append(f"{indent}# [MIGRATED] {line_stripped}\n")
                    new_lines.append(f"{indent}{translated}\n")
                    file_modified = True
                else:
                    new_lines.append(line)
            else:
                report.add_complex(filepath, idx+1, full_command, "Translation Failed/Unsupported")
                new_lines.append(line)
        else:
            new_lines.append(line)

    if convert_mode and file_modified:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)
            # print(f"[\033[92mFIXED\033[0m] {filepath}") # Optional: Silent mode for large builds
        except Exception as e:
            print(f"[\033[91mERR\033[0m] Could not write {filepath}: {e}")

def main():
    parser = argparse.ArgumentParser(description="ROCKNIX Recursive Migration Tool")
    parser.add_argument("path", help="Root directory to scan recursively")
    parser.add_argument("--convert", action="store_true", help="Apply in-place conversions")
    args = parser.parse_args()

    if args.convert:
        if subprocess.call(["which", "iptables-translate"], stdout=subprocess.DEVNULL) != 0:
            print("Error: 'iptables-translate' not found. Please install it.")
            sys.exit(1)

    report = Report()
    
    # Progress counters
    scanned_count = 0
    found_count = 0

    print(f"Recursively scanning: {os.path.abspath(args.path)}")
    print("(Press Ctrl+C to abort)")

    # RECURSIVE WALK
    # followlinks=True ensures we follow symlinks to other directories
    for root, dirs, files in os.walk(args.path, followlinks=True):
        
        # Cleanup search space
        if '.git' in dirs: dirs.remove('.git')
        if 'build' in dirs: dirs.remove('build') # Skip build artifacts
        if 'overlays' in dirs: dirs.remove('overlays') # Optional: Skip overlay fs if irrelevant

        # Visual Feedback
        sys.stdout.write(f"\rScanning: {root[:80]:<80}")
        sys.stdout.flush()

        for file in files:
            filepath = os.path.join(root, file)
            _, ext = os.path.splitext(file)

            # Skip explicit ignores
            if ext in IGNORE_EXTENSIONS:
                continue

            # Logic: Scan if Extension is known OR if file is extensionless text
            should_scan = False
            if ext in TEXT_EXTENSIONS or ext in PATCH_EXTENSIONS:
                should_scan = True
            elif ext == "":
                should_scan = is_text_file(filepath)
            
            if should_scan:
                scanned_count += 1
                scan_file(filepath, report, args.convert)

    # --- RESULTS ---
    sys.stdout.write("\r" + " " * 80 + "\r") # Clear progress line
    print("\n" + "="*60)
    print("  ROCKNIX MIGRATION REPORT  ")
    print("="*60)

    # Report Simple
    if report.simple:
        print(f"\n\033[92m[SIMPLE] Auto-Convertible ({len(report.simple)} files):\033[0m")
        for f, items in report.simple.items():
            print(f"  {f}")
            for i in items:
                print(f"    Line {i['line']}: {i['orig']}")
                print(f"       -> {i['conv']}")

    # Report Complex
    if report.complex:
        print(f"\n\033[91m[COMPLEX] Manual Intervention Needed ({len(report.complex)} files):\033[0m")
        for f, items in report.complex.items():
            print(f"  {f}")
            for i in items:
                print(f"    Line {i['line']} [{i['reason']}]: {i['orig']}")

    print("-" * 60)
    print(f"Files Scanned: {scanned_count}")
    print(f"Simple Cases:  {sum(len(v) for v in report.simple.values())}")
    print(f"Complex Cases: {sum(len(v) for v in report.complex.values())}")
    
    if not args.convert:
        print("\nNOTE: This was a dry run. Use --convert to apply changes to Simple items.")
    else:
        print("\nSUCCESS: In-place conversion applied.")

if __name__ == "__main__":
    main()
