#!/usr/bin/env bash

# Flutter/Dart Monorepo Package Manager
# Fixed and improved version with robust error handling

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Determine directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Initialize global arrays for package info
declare -a package_paths=()
declare -a package_names=()
declare -a package_versions=()
package_count=0

# Selection result variables
declare -i selection_result=0
declare -a selection_results=()
declare -i selected_count=0
declare -a selected_indices=()

# Clean up helper
cleanup() {
  local exit_code=$?
  tput cnorm 2>/dev/null || true
  # Only print goodbye on error/interrupt, not normal exit
  if [ $exit_code -ne 0 ]; then
    echo -e "\n${RED}Exiting with error. Goodbye!${NC}"
  fi
}
trap cleanup EXIT INT TERM

# Read keyboard inputs, capturing arrow keys, space, and letters
get_key() {
  local key
  IFS= read -rs -n1 key 2>/dev/null || true
  if [[ "$key" == $'\e' ]]; then
    local rest
    IFS= read -rs -n2 -t 1 rest 2>/dev/null || true
    key="${key}${rest}"
    if [[ "$key" == $'\e[A' || "$key" == $'\eOA' ]]; then
      echo "up"
    elif [[ "$key" == $'\e[B' || "$key" == $'\eOB' ]]; then
      echo "down"
    elif [[ "$key" == $'\e[H' || "$key" == $'\e[1~' ]]; then
      echo "home"
    elif [[ "$key" == $'\e[F' || "$key" == $'\e[4~' ]]; then
      echo "end"
    else
      echo "unknown"
    fi
  elif [[ "$key" == "" ]]; then
    echo "enter"
  elif [[ "$key" == " " ]]; then
    echo "space"
  else
    echo "$key"
  fi
}

# Render a single-select radio button menu
# Returns the 0-based selected index in selection_result
select_menu_radio() {
  local prompt="$1"
  local current="$2"
  shift 2
  local options=("$@")
  local count=${#options[@]}

  if [ $count -eq 0 ]; then
    echo -e "${RED}Error: No options provided for radio menu.${NC}"
    return 1
  fi

  tput civis 2>/dev/null || true
  tput sc 2>/dev/null || true

  while true; do
    tput rc 2>/dev/null || true
    tput ed 2>/dev/null || true

    echo -e "${BOLD}$prompt${NC}"
    for ((i=0; i<count; i++)); do
      if [ $i -eq $current ]; then
        echo -e "  ${GREEN}►${NC} ${CYAN}(*)${NC} ${BOLD}${options[i]}${NC}"
      else
        echo -e "    ( ) ${options[i]}"
      fi
    done
    echo -e "${YELLOW}↑/↓ to navigate, Enter to select, q to quit${NC}"

    local key
    key=$(get_key)

    case "$key" in
      "up")
        current=$(( (current - 1 + count) % count ))
        ;;
      "down")
        current=$(( (current + 1) % count ))
        ;;
      "home")
        current=0
        ;;
      "end")
        current=$(( count - 1 ))
        ;;
      "enter")
        break
        ;;
      "q"|"Q")
        tput rc 2>/dev/null || true
        tput ed 2>/dev/null || true
        tput cnorm 2>/dev/null || true
        exit 0
        ;;
    esac
  done

  tput cnorm 2>/dev/null || true

  # Print final choice in place
  tput rc 2>/dev/null || true
  tput ed 2>/dev/null || true
  echo -e "${BOLD}$prompt${NC}"
  for ((i=0; i<count; i++)); do
    if [ $i -eq $current ]; then
      echo -e "    ${GREEN}(*)${NC} ${BOLD}${options[i]}${NC}"
    else
      echo -e "    ( ) ${options[i]}"
    fi
  done
  echo ""

  selection_result=$current
}

# Render a multi-select checkbox menu
# Returns the selected 0-based indices in selection_results array
select_menu_checkbox() {
  local prompt="$1"
  shift
  local options=("$@")
  local count=${#options[@]}
  local cursor=0

  if [ $count -eq 0 ]; then
    echo -e "${RED}Error: No options provided for checkbox menu.${NC}"
    return 1
  fi

  # Initialize checkboxes
  local checked=()
  for ((i=0; i<count; i++)); do
    checked[i]=0
  done

  tput civis 2>/dev/null || true
  tput sc 2>/dev/null || true

  while true; do
    tput rc 2>/dev/null || true
    tput ed 2>/dev/null || true

    echo -e "${BOLD}$prompt${NC}"
    echo -e "${YELLOW}↑/↓ navigate, Space toggle, a=all, n=none, Enter confirm, q=quit${NC}"
    for ((i=0; i<count; i++)); do
      local checkbox="[ ]"
      if [ ${checked[i]} -eq 1 ]; then
        checkbox="[${GREEN}x${NC}]"
      fi

      if [ $i -eq $cursor ]; then
        echo -e "  ${GREEN}►${NC} $checkbox ${BOLD}${options[i]}${NC}"
      else
        echo -e "    $checkbox ${options[i]}"
      fi
    done

    local key
    key=$(get_key)

    case "$key" in
      "up")
        cursor=$(( (cursor - 1 + count) % count ))
        ;;
      "down")
        cursor=$(( (cursor + 1) % count ))
        ;;
      "home")
        cursor=0
        ;;
      "end")
        cursor=$(( count - 1 ))
        ;;
      "space")
        if [ ${checked[cursor]} -eq 1 ]; then
          checked[cursor]=0
        else
          checked[cursor]=1
        fi
        ;;
      "a"|"A")
        for ((i=0; i<count; i++)); do
          checked[i]=1
        done
        ;;
      "n"|"N")
        for ((i=0; i<count; i++)); do
          checked[i]=0
        done
        ;;
      "enter")
        break
        ;;
      "q"|"Q")
        tput rc 2>/dev/null || true
        tput ed 2>/dev/null || true
        tput cnorm 2>/dev/null || true
        exit 0
        ;;
    esac
  done

  tput cnorm 2>/dev/null || true

  tput rc 2>/dev/null || true
  tput ed 2>/dev/null || true

  # Print final selections in place
  echo -e "${BOLD}$prompt${NC}"
  echo -e "${GREEN}Confirmed selections:${NC}"
  selection_results=()
  local sel_idx=0
  for ((i=0; i<count; i++)); do
    if [ ${checked[i]} -eq 1 ]; then
      echo -e "    [${GREEN}x${NC}] ${options[i]}"
      selection_results[sel_idx]=$i
      sel_idx=$((sel_idx + 1))
    fi
  done
  if [ $sel_idx -eq 0 ]; then
    echo -e "    ${YELLOW}(None selected)${NC}"
  fi
  echo ""

  selected_count=$sel_idx
}

# Discover all packages containing a pubspec.yaml
discover_packages() {
  package_count=0
  package_paths=()
  package_names=()
  package_versions=()

  # Find all pubspec.yaml files up to depth 3
  # CRITICAL FIX: -maxdepth must come BEFORE -name
  while IFS= read -r pubspec; do
    # Skip build/, .dart_tool/, and example/ directories
    if [[ "$pubspec" == *"/build/"* || "$pubspec" == *"/.dart_tool/"* || "$pubspec" == *"/example/"* ]]; then
      continue
    fi

    local name=""
    local version=""
    while IFS= read -r line || [ -n "$line" ]; do
      # FIX: More precise regex - match exactly "name:" at start of line
      if [[ "$line" =~ ^name:[[:space:]]+(.+) ]]; then
        name="${BASH_REMATCH[1]}"
        name=$(echo "$name" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # FIX: More precise regex - match exactly "version:" at start of line
      elif [[ "$line" =~ ^version:[[:space:]]+(.+) ]]; then
        version="${BASH_REMATCH[1]}"
        version=$(echo "$version" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      fi
    done < "$pubspec"

    if [ -n "$name" ]; then
      local dir_path
      dir_path=$(dirname "$pubspec")
      local rel_path=""
      if [ "$dir_path" != "$ROOT_DIR" ]; then
        rel_path="${dir_path#$ROOT_DIR/}"
      fi

      package_paths[package_count]="$rel_path"
      package_names[package_count]="$name"
      package_versions[package_count]="$version"
      package_count=$((package_count + 1))
    fi
  done < <(find "$ROOT_DIR" -maxdepth 3 -name "pubspec.yaml" | sort)
}

# Helper to run commands using FVM or global Flutter/Dart
# FIX: Better FVM detection - search up the directory tree
run_flutter_cmd() {
  local dir="$1"
  shift
  local args=("$@")

  (
    cd "$dir" || return 1

    # FIX: Search up the directory tree for .fvmrc or .fvm/ directory
    local check_dir="$PWD"
    local use_fvm=false
    while [ "$check_dir" != "/" ]; do
      if [ -f "$check_dir/.fvmrc" ] || [ -d "$check_dir/.fvm" ]; then
        use_fvm=true
        break
      fi
      check_dir=$(dirname "$check_dir")
    done

    if [ "$use_fvm" = true ] && command -v fvm &> /dev/null; then
      fvm flutter "${args[@]}"
    elif command -v flutter &> /dev/null; then
      flutter "${args[@]}"
    elif command -v dart &> /dev/null; then
      # Fallback to dart for pure Dart packages
      dart "${args[@]}"
    else
      echo -e "${RED}Error: Neither fvm, flutter, nor dart command was found on the PATH.${NC}"
      return 1
    fi
  )
}

# Helper to run commands using FVM dart or global Dart
run_dart_cmd() {
  local dir="$1"
  shift
  local args=("$@")

  (
    cd "$dir" || return 1

    local check_dir="$PWD"
    local use_fvm=false
    while [ "$check_dir" != "/" ]; do
      if [ -f "$check_dir/.fvmrc" ] || [ -d "$check_dir/.fvm" ]; then
        use_fvm=true
        break
      fi
      check_dir=$(dirname "$check_dir")
    done

    if [ "$use_fvm" = true ] && command -v fvm &> /dev/null; then
      fvm dart "${args[@]}"
    elif command -v dart &> /dev/null; then
      dart "${args[@]}"
    elif command -v flutter &> /dev/null; then
      # Fallback to dart via flutter wrapper if dart isn't directly on PATH
      flutter dart "${args[@]}"
    else
      echo -e "${RED}Error: Neither fvm, dart, nor flutter command was found on the PATH.${NC}"
      return 1
    fi
  )
}

# Check if a package is a Flutter package (has flutter dependency)
is_flutter_package() {
  local pubspec_path="$1"
  grep -q "sdk:\s*flutter" "$pubspec_path" 2>/dev/null ||     grep -q "flutter:" "$pubspec_path" 2>/dev/null
}

# Create backup of a file before modification
backup_file() {
  local file="$1"
  local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$file" "$backup"
  echo "$backup"
}

# Select packages interactively
# Sets the global selected_indices array
select_packages() {
  selected_indices=()
  selected_count=0

  if [ $package_count -eq 0 ]; then
    echo -e "${RED}No packages discovered. Run from a Flutter/Dart monorepo root.${NC}"
    return 1
  fi

  local menu_options=()
  for ((i=0; i<package_count; i++)); do
    local rel_path="${package_paths[i]}"
    local display_path="[root]"
    if [ -n "$rel_path" ]; then
      display_path="./$rel_path"
    fi
    menu_options[i]="${package_names[i]} (v${package_versions[i]}) - $display_path"
  done

  select_menu_checkbox "Select packages for the operation:" "${menu_options[@]}"

  if [ $selected_count -eq 0 ]; then
    echo -e "${YELLOW}No packages selected. Operation cancelled.${NC}"
    return 1
  fi

  selected_indices=("${selection_results[@]}")
  return 0
}

# Validate semantic version format
validate_version() {
  local version="$1"
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-].*)?$ ]]; then
    return 0
  else
    return 1
  fi
}

# 1. Change package version
change_versions() {
  if ! select_packages; then return; fi

  echo ""
  local bulk_version=""
  read -rp "Enter a version to apply to ALL selected packages (e.g., 1.2.3, leave blank for individual): " bulk_version
  bulk_version=$(echo "$bulk_version" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -n "$bulk_version" ] && ! validate_version "$bulk_version"; then
    echo -e "${YELLOW}Warning: '$bulk_version' doesn't look like a standard semantic version.${NC}"
    read -rp "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Version change cancelled.${NC}"
      return
    fi
  fi

  for ((i=0; i<selected_count; i++)); do
    local idx="${selected_indices[i]}"
    local pkg_name="${package_names[idx]}"
    local rel_path="${package_paths[idx]}"
    local pubspec_path="$ROOT_DIR/pubspec.yaml"
    if [ -n "$rel_path" ]; then
      pubspec_path="$ROOT_DIR/$rel_path/pubspec.yaml"
    fi

    local target_version=""
    if [ -n "$bulk_version" ]; then
      target_version="$bulk_version"
    else
      read -rp "New version for $pkg_name (current: ${package_versions[idx]}): " input_version
      target_version=$(echo "$input_version" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$target_version" ]; then
        echo -e "${YELLOW}Skipping $pkg_name version update.${NC}"
        continue
      fi
      if ! validate_version "$target_version"; then
        echo -e "${YELLOW}Warning: '$target_version' doesn't look like a standard semantic version.${NC}"
        read -rp "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
          echo -e "${YELLOW}Skipping $pkg_name version update.${NC}"
          continue
        fi
      fi
    fi

    # FIX: Create backup before modification
    local backup
    backup=$(backup_file "$pubspec_path")

    # FIX: More precise regex - match exactly "version:" at start of line
    # Use perl with word boundary to avoid matching flutter_version, dart_version, etc.
    if perl -pi -e "s/^(version:[[:space:]]+).*/\${1}$target_version/" "$pubspec_path"; then
      echo -e "${GREEN}✓ Updated $pkg_name version to $target_version${NC}"
      # Remove backup on success
      rm -f "$backup"
    else
      echo -e "${RED}✗ Failed to update $pkg_name version. Restoring from backup...${NC}"
      cp "$backup" "$pubspec_path"
      rm -f "$backup"
    fi
  done

  # Rediscover to update versions cache
  discover_packages
}

# 2. Run pub get
run_pub_get() {
  if ! select_packages; then return; fi

  echo -e "\n${BLUE}Running pub get on selected packages...${NC}"
  local failed=0
  for ((i=0; i<selected_count; i++)); do
    local idx="${selected_indices[i]}"
    local pkg_name="${package_names[idx]}"
    local rel_path="${package_paths[idx]}"
    local dir_path="$ROOT_DIR"
    if [ -n "$rel_path" ]; then
      dir_path="$ROOT_DIR/$rel_path"
    fi

    echo -e "\n${BOLD}=== [$pkg_name] flutter pub get ===${NC}"
    if run_flutter_cmd "$dir_path" pub get; then
      echo -e "${GREEN}✓ SUCCESS: pub get in $pkg_name${NC}"
    else
      echo -e "${RED}✗ FAILED: pub get in $pkg_name${NC}"
      failed=$((failed + 1))
    fi
  done

  if [ $failed -gt 0 ]; then
    echo -e "\n${RED}$failed package(s) failed pub get.${NC}"
  else
    echo -e "\n${GREEN}All packages updated successfully!${NC}"
  fi
}

# 3. Switch Dependencies (DEV / PROD)
# FIX: Completely rewritten with proper YAML parsing using Python
declare -r PYTHON_TOGGLE_SCRIPT=$(cat << 'PYTHON_EOF'
import os
import sys
import json
import re
import shutil

def parse_pubspec(path):
    """Parse pubspec.yaml into structured sections."""
    with open(path, 'r') as f:
        content = f.read()

    lines = content.split('\n')
    sections = {}
    current_section = None
    section_lines = []

    for line in lines:
        is_override_comment = re.match(r'^#\s*(dependency_overrides):\s*$', line)
        if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*:\s*$', line) or re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*:\s+', line) or is_override_comment:
            if current_section:
                sections[current_section] = section_lines
            if is_override_comment:
                current_section = 'dependency_overrides'
            else:
                current_section = line.split(':')[0].strip()
            section_lines = [line]
        elif current_section:
            section_lines.append(line)
        else:
            # Lines before first section (shouldn't happen in valid pubspec)
            if '_preamble' not in sections:
                sections['_preamble'] = []
            sections['_preamble'].append(line)

    if current_section:
        sections[current_section] = section_lines

    return sections, content

def extract_dependencies(section_lines, sibling_names, filter_siblings=False):
    """Extract package names from a dependency section."""
    deps = {}
    current_pkg = None
    current_block = []

    for line in section_lines[1:]:  # Skip section header
        stripped = line.strip()
        
        # Discard empty lines completely inside the dependencies parsing to prevent accumulation
        if not stripped:
            continue

        # Skip sibling-related lines and auto-managed markers completely if filtering
        if filter_siblings:
            is_sibling_related = False
            if "Auto-managed" in line:
                is_sibling_related = True
            else:
                for name in sibling_names:
                    if name in line:
                        is_sibling_related = True
                        break
            if is_sibling_related:
                continue

        if stripped.startswith('#'):
            if current_pkg:
                current_block.append(line)
            continue

        # Check if this is a new dependency indented by exactly 2 spaces
        if re.match(r'^  ([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$', line):
            if current_pkg:
                deps[current_pkg] = current_block
            pkg_match = re.match(r'^  ([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$', line)
            current_pkg = pkg_match.group(1)
            current_block = [line]
        elif current_pkg:
            current_block.append(line)

    if current_pkg:
        deps[current_pkg] = current_block

    return deps

def build_dependency_block(pkg_name, version, rel_path, mode, indent=2):
    """Build dependency lines for a package."""
    lines = []
    sp = ' ' * indent
    if mode == 'dev':
        lines.append(f"{sp}# {pkg_name}: ^{version}")
        lines.append(f"{sp}{pkg_name}:")
        lines.append(f"{sp}  path: {rel_path}")
    else:
        lines.append(f"{sp}{pkg_name}: ^{version}")
        lines.append(f"{sp}# {pkg_name}:")
        lines.append(f"{sp}#   path: {rel_path}")
    return lines

def build_override_block(pkg_name, rel_path, indent=2):
    """Build override lines for a package."""
    lines = []
    sp = ' ' * indent
    lines.append(f"{sp}{pkg_name}:")
    lines.append(f"{sp}  path: {rel_path}")
    return lines

def main():
    root_dir = os.environ['ROOT_DIR']
    pubspec_path = os.environ['TARGET_PUBSPEC']
    mode = os.environ['MODE']
    siblings = json.loads(os.environ['SIBLINGS'])

    target_dir = os.path.dirname(os.path.abspath(pubspec_path))

    # Create backup
    backup_path = pubspec_path + '.backup'
    shutil.copy2(pubspec_path, backup_path)

    try:
        sections, original_content = parse_pubspec(pubspec_path)

        # Build sibling lookup
        sibling_names = {s['name'] for s in siblings}

        # Find sibling packages referenced in dependencies/dev_dependencies separately
        referenced_deps = []
        referenced_dev_deps = []

        if 'dependencies' in sections:
            deps = extract_dependencies(sections['dependencies'], sibling_names, filter_siblings=False)
            for pkg_name in deps:
                if pkg_name in sibling_names:
                    for sib in siblings:
                        if sib['name'] == pkg_name:
                            referenced_deps.append(sib)
                            break

        if 'dev_dependencies' in sections:
            dev_deps = extract_dependencies(sections['dev_dependencies'], sibling_names, filter_siblings=False)
            for pkg_name in dev_deps:
                if pkg_name in sibling_names:
                    for sib in siblings:
                        if sib['name'] == pkg_name:
                            referenced_dev_deps.append(sib)
                            break

        if not referenced_deps and not referenced_dev_deps:
            print(f"  No sibling dependencies to toggle in {os.path.basename(pubspec_path)}")
            os.remove(backup_path)
            return

        print(f"  Toggling {len(referenced_deps) + len(referenced_dev_deps)} sibling(s) in {os.path.basename(pubspec_path)} to {mode.upper()} mode...")

        # Process each section
        new_sections = {}
        for section_name, lines in sections.items():
            if section_name == 'dependencies':
                new_lines = [lines[0]]
                deps = extract_dependencies(lines, sibling_names, filter_siblings=True)
                for pkg_name, block in deps.items():
                    if pkg_name not in sibling_names:
                        new_lines.extend(block)
                if referenced_deps:
                    new_lines.append("  # --- Sibling Dependencies (Auto-managed) ---")
                    for sib in referenced_deps:
                        sib_dir = os.path.abspath(os.path.join(root_dir, sib['path']))
                        rel_path = os.path.relpath(sib_dir, target_dir)
                        new_lines.extend(build_dependency_block(sib['name'], sib['version'], rel_path, mode))
                new_sections[section_name] = new_lines
            elif section_name == 'dev_dependencies':
                new_lines = [lines[0]]
                deps = extract_dependencies(lines, sibling_names, filter_siblings=True)
                for pkg_name, block in deps.items():
                    if pkg_name not in sibling_names:
                        new_lines.extend(block)
                if referenced_dev_deps:
                    new_lines.append("  # --- Sibling Dependencies (Auto-managed) ---")
                    for sib in referenced_dev_deps:
                        sib_dir = os.path.abspath(os.path.join(root_dir, sib['path']))
                        rel_path = os.path.relpath(sib_dir, target_dir)
                        new_lines.extend(build_dependency_block(sib['name'], sib['version'], rel_path, mode))
                new_sections[section_name] = new_lines
            elif section_name == 'dependency_overrides':
                # Skip - we'll rebuild this at the end
                continue
            else:
                new_sections[section_name] = lines

        # Build dependency_overrides section
        override_lines = []
        non_sibling_overrides = []
        if 'dependency_overrides' in sections:
            deps = extract_dependencies(sections['dependency_overrides'], sibling_names, filter_siblings=True)
            for pkg_name, block in deps.items():
                if pkg_name not in sibling_names:
                    non_sibling_overrides.extend(block)

        referenced_all = referenced_deps + referenced_dev_deps

        if referenced_all or non_sibling_overrides:
            override_lines.append("# --- Sibling Overrides (Auto-managed) ---")
            override_lines.append("dependency_overrides:")
            override_lines.extend(non_sibling_overrides)
            for sib in referenced_all:
                sib_dir = os.path.abspath(os.path.join(root_dir, sib['path']))
                rel_path = os.path.relpath(sib_dir, target_dir)
                override_lines.extend(build_override_block(sib['name'], rel_path))

        new_sections['dependency_overrides'] = override_lines

        # Write back
        with open(pubspec_path, 'w') as f:
            for section_name in ['_preamble', 'name', 'description', 'version', 'homepage', 'repository', 
                                 'issue_tracker', 'documentation', 'publish_to', 'environment',
                                 'dependencies', 'dev_dependencies', 'dependency_overrides']:
                if section_name in new_sections:
                    for line in new_sections[section_name]:
                        f.write(line + '\n')
            # Write any remaining sections
            for section_name, lines in new_sections.items():
                if section_name not in ['_preamble', 'name', 'description', 'version', 'homepage', 
                                        'repository', 'issue_tracker', 'documentation', 'publish_to', 
                                        'environment', 'dependencies', 'dev_dependencies', 'dependency_overrides']:
                    for line in lines:
                        f.write(line + '\n')

        os.remove(backup_path)

    except Exception as e:
        print(f"  ERROR: {e}")
        shutil.copy2(backup_path, pubspec_path)
        os.remove(backup_path)
        sys.exit(1)

if __name__ == '__main__':
    main()
PYTHON_EOF
)

switch_dependencies() {
  if ! select_packages; then return; fi

  select_menu_radio "Select dependency mode:" 0     "DEV (Path dependencies, overrides enabled)"     "PROD (Version dependencies, overrides disabled)"

  local mode=""
  if [ $selection_result -eq 0 ]; then
    mode="dev"
  else
    mode="prod"
  fi

  # Prepare sibling data as JSON
  local siblings_json="["
  for ((i=0; i<package_count; i++)); do
    if [ $i -ne 0 ]; then
      siblings_json="$siblings_json,"
    fi
    # FIX: Escape backslashes in paths for JSON
    local esc_path="${package_paths[i]}"
    esc_path="${esc_path//\/\\}"
    siblings_json="$siblings_json{\"name\":\"${package_names[i]}\",\"path\":\"$esc_path\",\"version\":\"${package_versions[i]}\"}"
  done
  siblings_json="$siblings_json]"

  export ROOT_DIR
  export SIBLINGS="$siblings_json"
  export MODE="$mode"

  local mode_upper
  mode_upper=$(echo "$mode" | tr '[:lower:]' '[:upper:]')
  echo -e "\n${BLUE}Switching sibling dependencies to ${mode_upper} mode...${NC}"

  local failed=0
  for ((i=0; i<selected_count; i++)); do
    local idx="${selected_indices[i]}"
    local rel_path="${package_paths[idx]}"
    local pubspec_path="$ROOT_DIR/pubspec.yaml"
    if [ -n "$rel_path" ]; then
      pubspec_path="$ROOT_DIR/$rel_path/pubspec.yaml"
    fi

    export TARGET_PUBSPEC="$pubspec_path"

    if python3 -c "$PYTHON_TOGGLE_SCRIPT"; then
      echo -e "${GREEN}✓ Updated ${package_names[idx]}${NC}"
    else
      echo -e "${RED}✗ Failed to update ${package_names[idx]}${NC}"
      failed=$((failed + 1))
    fi
  done

  # Clean up env
  unset SIBLINGS
  unset MODE
  unset TARGET_PUBSPEC

  if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Dependency toggle complete! Running 'pub get' is recommended.${NC}"
  else
    echo -e "${RED}$failed package(s) failed to toggle. Check backups (.backup files).${NC}"
  fi
}

# 4. Run analyze
run_analyze() {
  if ! select_packages; then return; fi

  echo -e "\n${BLUE}Running analyzer on selected packages...${NC}"
  local failed=0
  for ((i=0; i<selected_count; i++)); do
    local idx="${selected_indices[i]}"
    local pkg_name="${package_names[idx]}"
    local rel_path="${package_paths[idx]}"
    local dir_path="$ROOT_DIR"
    if [ -n "$rel_path" ]; then
      dir_path="$ROOT_DIR/$rel_path"
    fi
    local pubspec_path="$dir_path/pubspec.yaml"

    echo -e "\n${BOLD}=== [$pkg_name] flutter analyze ===${NC}"

    # FIX: Use dart analyze for pure Dart packages
    if is_flutter_package "$pubspec_path"; then
      if run_flutter_cmd "$dir_path" analyze; then
        echo -e "${GREEN}✓ SUCCESS: Analysis passed for $pkg_name${NC}"
      else
        echo -e "${RED}✗ FAILED: Analysis errors in $pkg_name${NC}"
        failed=$((failed + 1))
      fi
    else
      if run_flutter_cmd "$dir_path" analyze; then
        echo -e "${GREEN}✓ SUCCESS: Analysis passed for $pkg_name${NC}"
      else
        echo -e "${RED}✗ FAILED: Analysis errors in $pkg_name${NC}"
        failed=$((failed + 1))
      fi
    fi
  done

  if [ $failed -gt 0 ]; then
    echo -e "\n${RED}$failed package(s) had analysis errors.${NC}"
  else
    echo -e "\n${GREEN}All packages passed analysis!${NC}"
  fi
}

# 5. Run tests
run_tests() {
  if ! select_packages; then return; fi

  echo -e "\n${BLUE}Running tests on selected packages...${NC}"
  local failed=0
  local skipped=0
  for ((i=0; i<selected_count; i++)); do
    local idx="${selected_indices[i]}"
    local pkg_name="${package_names[idx]}"
    local rel_path="${package_paths[idx]}"
    local dir_path="$ROOT_DIR"
    if [ -n "$rel_path" ]; then
      dir_path="$ROOT_DIR/$rel_path"
    fi

    # FIX: Check for actual test files, not just directory
    if [ -d "$dir_path/test" ] && [ -n "$(find "$dir_path/test" -name "*_test.dart" -print -quit 2>/dev/null)" ]; then
      echo -e "\n${BOLD}=== [$pkg_name] flutter test ===${NC}"
      if run_flutter_cmd "$dir_path" test; then
        echo -e "${GREEN}✓ SUCCESS: Tests passed for $pkg_name${NC}"
      else
        echo -e "${RED}✗ FAILED: Tests failed in $pkg_name${NC}"
        failed=$((failed + 1))
      fi
    else
      echo -e "${YELLOW}⚠ Skip $pkg_name: No test files found.${NC}"
      skipped=$((skipped + 1))
    fi
  done

  echo -e "\n${BLUE}Test Summary:${NC}"
  echo -e "  ${GREEN}Passed:${NC} $((selected_count - failed - skipped))"
  echo -e "  ${RED}Failed:${NC} $failed"
  echo -e "  ${YELLOW}Skipped:${NC} $skipped"
}

# 6. Run format
run_format() {
  if ! select_packages; then return; fi

  echo -e "\n${BLUE}Formatting code on selected packages...${NC}"
  local failed=0
  for ((i=0; i<selected_count; i++)); do
    local idx="${selected_indices[i]}"
    local pkg_name="${package_names[idx]}"
    local rel_path="${package_paths[idx]}"
    local dir_path="$ROOT_DIR"
    if [ -n "$rel_path" ]; then
      dir_path="$ROOT_DIR/$rel_path"
    fi

    echo -e "\n${BOLD}=== [$pkg_name] dart format . ===${NC}"
    if run_dart_cmd "$dir_path" format .; then
      echo -e "${GREEN}✓ SUCCESS: Formatting completed for $pkg_name${NC}"
    else
      echo -e "${RED}✗ FAILED: Formatting failed in $pkg_name${NC}"
      failed=$((failed + 1))
    fi
  done

  if [ $failed -gt 0 ]; then
    echo -e "\n${RED}$failed package(s) failed formatting.${NC}"
  else
    echo -e "\n${GREEN}All packages formatted successfully!${NC}"
  fi
}

# 7. Show package info
show_package_info() {
  discover_packages

  echo -e "\n${BOLD}====================================================${NC}"
  echo -e "${BOLD}      Discovered Packages${NC}"
  echo -e "${BOLD}====================================================${NC}"

  if [ $package_count -eq 0 ]; then
    echo -e "${RED}No packages found. Ensure this is run from a Flutter/Dart monorepo.${NC}"
    return
  fi

  for ((i=0; i<package_count; i++)); do
    local rel_path="${package_paths[i]}"
    local display_path="[root]"
    if [ -n "$rel_path" ]; then
      display_path="./$rel_path"
    fi

    local is_flutter=""
    local pubspec_path="$ROOT_DIR/pubspec.yaml"
    if [ -n "$rel_path" ]; then
      pubspec_path="$ROOT_DIR/$rel_path/pubspec.yaml"
    fi
    if is_flutter_package "$pubspec_path"; then
      is_flutter=" ${CYAN}(Flutter)${NC}"
    else
      is_flutter=" ${MAGENTA}(Dart)${NC}"
    fi

    echo -e "${BOLD}${package_names[i]}${NC} ${GREEN}v${package_versions[i]}${NC}$is_flutter"
    echo -e "  Path: $display_path"

    # Count dependencies
    local deps_count=0
    if [ -f "$pubspec_path" ]; then
      deps_count=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_-]*:" "$pubspec_path" 2>/dev/null || echo 0)
      # Subtract known non-dependency sections (approximate)
      deps_count=$((deps_count - 5))
      if [ $deps_count -lt 0 ]; then deps_count=0; fi
    fi
    echo -e "  Dependencies: ~$deps_count"
    echo ""
  done
}

# Main event loop
main() {
  discover_packages

  while true; do
    echo -e "\n${BOLD}====================================================${NC}"
    echo -e "${BOLD}      Package Settings Manager (${CYAN}federated setup${NC}${BOLD})${NC}"
    echo -e "${BOLD}====================================================${NC}"

    if [ $package_count -gt 0 ]; then
      echo -e "${GREEN}$package_count package(s) discovered${NC}"
    else
      echo -e "${YELLOW}No packages discovered yet${NC}"
    fi
    echo ""

    select_menu_radio "Select action:" 0 \
      "📦 Change package version" \
      "📥 Run pub get (flutter pub get)" \
      "🔄 Toggle dependencies (DEV / PROD mode)" \
      "🔍 Analyze packages (flutter analyze)" \
      "🧪 Test packages (flutter test)" \
      "✨ Format code (dart format)" \
      "ℹ️  Show package info" \
      "🚪 Exit"

    local action=$((selection_result + 1))

    case "$action" in
      1) change_versions ;;
      2) run_pub_get ;;
      3) switch_dependencies ;;
      4) run_analyze ;;
      5) run_tests ;;
      6) run_format ;;
      7) show_package_info ;;
      8) 
        echo -e "\n${GREEN}Goodbye!${NC}"
        exit 0 
        ;;
    esac
  done
}

main