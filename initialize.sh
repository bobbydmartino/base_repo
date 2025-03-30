#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
DEFAULT_BRANCH="main"
DEFAULT_AUTHOR_NAME=$(git config user.name || echo "Your Name")
DEFAULT_AUTHOR_EMAIL=$(git config user.email || echo "your.email@example.com")

# --- Helper Functions ---

# Helper function for colored output
color_echo() {
    local color_code="$1"
    local message="$2"
    echo -e "\e[${color_code}m${message}\e[0m"
}

green() { color_echo "32" "$1"; }
yellow() { color_echo "33" "$1"; }
blue() { color_echo "34" "$1"; }
red() { color_echo "31" "$1"; }

# Helper function for user prompts with defaults
prompt_user() {
    local prompt_message="$1"
    local default_value="$2"
    local variable_name="$3"
    local options_prompt="$4" # Optional: Add (y/n) or similar hints

    if [ -n "$default_value" ]; then
        prompt_message="$prompt_message [$default_value]"
    fi
    if [ -n "$options_prompt" ]; then
        prompt_message="$prompt_message $options_prompt"
    fi

    read -p "$(blue "$prompt_message: ")" user_input
    eval "$variable_name=\"${user_input:-$default_value}\""
}

prompt_yes_no() {
    local prompt_message="$1"
    local default_yes="$2" # Set to "y" if default should be yes
    local variable_name="$3"
    local default_prompt="y/N"
    local default_val="n"

    if [[ "${default_yes,,}" == "y" ]]; then
        default_prompt="Y/n"
        default_val="y"
    fi

    while true; do
        prompt_user "$prompt_message" "$default_val" user_input "($default_prompt)"
        case "${user_input,,}" in
            y|yes) eval "$variable_name=y"; break ;;
            n|no) eval "$variable_name=n"; break ;;
            *) red "Invalid input. Please enter 'yes' or 'no'." ;;
        esac
    done
}

# --- Main Script Logic ---

# 1. Get Project Name
# Use current directory name as default if initialize.sh is run inside an empty dir?
# For now, stick to prompting.
prompt_user "Enter the new project name" "" NEW_NAME
if [ -z "$NEW_NAME" ]; then
    red "Project name cannot be empty."
    exit 1
fi
if [ -e "../$NEW_NAME" ]; then
    red "Directory ../$NEW_NAME already exists."
    exit 1
fi

green "Creating project '$NEW_NAME'..."
mkdir "../$NEW_NAME"
cd "../$NEW_NAME"

# 2. Component Selection
yellow "\n--- Project Components ---"
prompt_yes_no "Create README.md?" "y" CREATE_README
prompt_yes_no "Create src/ directory (for Python code)?" "y" CREATE_SRC_DIR
prompt_yes_no "Create data/ directory?" "y" CREATE_DATA_DIR
prompt_yes_no "Create .gitignore?" "y" CREATE_GITIGNORE
prompt_yes_no "Create pyproject.toml (for Python packaging/tools)?" "y" CREATE_PYPROJECT
prompt_yes_no "Create basic requirements.txt?" "y" CREATE_REQUIREMENTS # Still useful for uv Dockerfile
prompt_yes_no "Setup Docker (Dockerfile & docker-compose.yml)?" "y" SETUP_DOCKER

# 3. Gather Details (if needed)
if [[ "$CREATE_PYPROJECT" == "y" ]]; then
    yellow "\n--- Python Project Details ---"
    prompt_user "Author Name" "$DEFAULT_AUTHOR_NAME" AUTHOR_NAME
    prompt_user "Author Email" "$DEFAULT_AUTHOR_EMAIL" AUTHOR_EMAIL
fi

DOCKER_BASE_IMAGE=""
DOCKER_USER_ACCESS="n"
DOCKER_USERNAME=""
DOCKER_INSTALL_DOTFILES="n"
DOCKER_NVIDIA_SUPPORT="n"
declare -A VOLUMES_TO_MOUNT # Use associative array for clarity

if [[ "$SETUP_DOCKER" == "y" ]]; then
    yellow "\n--- Docker Configuration ---"
    echo "Select Docker base image:"
    select DOCKER_BASE_CHOICE in "ubuntu:latest (Standard)" "nvidia/cuda:12.4.1-devel-ubuntu22.04 (CUDA)" "nvidia/cuda:11.8.0-devel-ubuntu22.04 (CUDA)" "Custom"; do
    # nvidia/cuda:12.6.2 doesn't exist as of checking, using 12.4.1 - adjust if needed
        case $DOCKER_BASE_CHOICE in
            "ubuntu:latest (Standard)") DOCKER_BASE_IMAGE="ubuntu:latest"; break;;
            "nvidia/cuda:12.4.1-devel-ubuntu22.04 (CUDA)") DOCKER_BASE_IMAGE="nvidia/cuda:12.4.1-devel-ubuntu22.04"; break;;
             "nvidia/cuda:11.8.0-devel-ubuntu22.04 (CUDA)") DOCKER_BASE_IMAGE="nvidia/cuda:11.8.0-devel-ubuntu22.04"; break;;
            "Custom") prompt_user "Enter custom base image name (e.g., python:3.11-slim)" "" DOCKER_BASE_IMAGE; break;;
            *) red "Invalid option $REPLY";;
        esac
    done

    prompt_yes_no "Install your dotfiles (runs docker_install.sh from bobbydmartino/.dotfiles)?" "n" DOCKER_INSTALL_DOTFILES
    prompt_yes_no "Require user access (non-root) inside container?" "n" DOCKER_USER_ACCESS
    if [[ "$DOCKER_USER_ACCESS" == "y" ]]; then
        prompt_user "Desired username" "user" DOCKER_USERNAME
        # Note: Password handling is basic. Consider security implications.
        # Using a fixed password or building without one might be better.
        yellow "Note: Setting a default password 'password' for $DOCKER_USERNAME."
        yellow "Change this in the Dockerfile or after container creation."
        DOCKER_PASSWORD="password"
    fi

    prompt_yes_no "Enable NVIDIA GPU support in docker-compose.yml?" "n" DOCKER_NVIDIA_SUPPORT

    # Volume Mounting - Check which standard dirs exist or will be created
    if [[ "$CREATE_SRC_DIR" == "y" ]]; then
        prompt_yes_no "Mount src/ directory as volume?" "y" MOUNT_SRC
        if [[ "$MOUNT_SRC" == "y" ]]; then VOLUMES_TO_MOUNT["src"]="/app/src"; fi # Map to /app/src inside container
    fi
     if [[ "$CREATE_DATA_DIR" == "y" ]]; then
        prompt_yes_no "Mount data/ directory as volume?" "y" MOUNT_DATA
        if [[ "$MOUNT_DATA" == "y" ]]; then VOLUMES_TO_MOUNT["data"]="/app/data"; fi # Map to /app/data
    fi
     # Add prompt for output dir?
    prompt_yes_no "Create and mount output/ directory as volume?" "y" MOUNT_OUTPUT
    if [[ "$MOUNT_OUTPUT" == "y" ]]; then
        mkdir -p output # Create if it doesn't exist
        VOLUMES_TO_MOUNT["output"]="/app/output";
        green "output/ directory created."
     fi
fi

# 4. Git Initialization Setup
yellow "\n--- Git Setup ---"
prompt_yes_no "Initialize Git repository?" "y" GIT_INIT
GIT_REMOTE_URL=""
if [[ "$GIT_INIT" == "y" ]]; then
    prompt_user "Branch name" "$DEFAULT_BRANCH" BRANCH_NAME
    prompt_user "Git remote origin URL (e.g., git@github.com:user/repo.git, leave blank to skip)" "" GIT_REMOTE_URL
fi

# --- File/Directory Creation ---

green "\nCreating selected files and directories..."

if [[ "$CREATE_README" == "y" ]]; then
    echo "# $NEW_NAME" > README.md
    echo "" >> README.md
    echo "Project initialized on $(date)" >> README.md
    green "README.md created."
fi

if [[ "$CREATE_SRC_DIR" == "y" ]]; then
    mkdir -p src
    touch src/__init__.py # Make it a package
    green "src/ directory created."
fi

if [[ "$CREATE_DATA_DIR" == "y" ]]; then
    mkdir -p data
    touch data/.gitkeep # Ensure directory is tracked by git even if empty
    green "data/ directory created."
fi

if [[ "$CREATE_GITIGNORE" == "y" ]]; then
    cat > .gitignore <<- EOM
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# C extensions
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
pip-wheel-metadata/
share/python-wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# PyInstaller
# Usually these files are written by a python script from a template
# before PyInstaller builds the exe, so as to inject date/other infos into it.
*.manifest
*.spec

# Installer logs
pip-log.txt
pip-delete-this-directory.txt

# Unit test / coverage reports
htmlcov/
.tox/
.nox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
*.py,cover
.hypothesis/
.pytest_cache/
cover/

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Spyder project settings
.spyderproject
.spyproject

# Rope project settings
.ropeproject

# mkdocs documentation
/site

# Jupyter Notebook
.ipynb_checkpoints

# IPython
profile_default/
ipython_config.py

# pyenv
.python-version

# PEP 582; used by PDM, Flit and pdm
__pypackages__/

# Celery stuff
celerybeat-schedule
celerybeat.pid

# SageMath parsed files
*.sage.py

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Editor directories and files
.vscode/
.idea/
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?

# Docker
.dockerignore
docker-compose.override.yml

# Data files
# data/ # Maybe too broad? Add specifics if needed.
output/

# uv cache
.uv_cache/

# OS generated files
.DS_Store
Thumbs.db
EOM
    green ".gitignore created."
fi

if [[ "$CREATE_REQUIREMENTS" == "y" ]]; then
    touch requirements.txt
    # Add common useful packages?
    # echo "python-dotenv" > requirements.txt
    green "requirements.txt created (empty)."
fi

if [[ "$CREATE_PYPROJECT" == "y" ]]; then
    # Use sed to replace placeholders in the template
    # Define the template within the script using a heredoc
    PYPROJECT_TEMPLATE=$(cat <<- EOM
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "<PROJ_NAME_PLACEHOLDER>"
version = "0.1.0"
description = "Description for <PROJ_NAME_PLACEHOLDER>"
authors = [
    { name = "<AUTHOR_NAME_PLACEHOLDER>", email = "<AUTHOR_EMAIL_PLACEHOLDER>" }
]
dependencies = [
    # Add your dependencies here, e.g.,
    # "requests",
    # "numpy",
]
requires-python = ">=3.9"

# Optional: Define scripts or entry points
# [project.scripts]
# my-script = "src.module:main_function"

[tool.hatch.build.targets.wheel]
packages = ["src"] # Point to your source directory

[tool.pytest.ini_options]
pythonpath = [".", "src"] # Add src to pythonpath

# Ruff configuration (linter and formatter)
[tool.ruff]
# Select rules: E/W (pycodestyle), F (Pyflakes), I (isort), N (pep8-naming),
# B (flake8-bugbear), A (flake8-builtins), C4 (flake8-comprehensions),
# PT (flake8-pytest-style), RET (flake8-return), SIM (flake8-simplify),
# TCH (flake8-type-checking), ARG (flake8-unused-arguments), TRY (tryceratops)
select = [
    "E", "W", "F", "I", "N", "B", "A", "C4", "PT", "RET", "SIM", "TCH", "ARG", "TRY"
    ]
ignore = []
fixable = ["ALL"]
unfixable = []
exclude = [
    ".bzr", ".direnv", ".eggs", ".git", ".git-rewrite", ".hg", ".mypy_cache",
    ".nox", ".pants.d", ".pytype", ".ruff_cache", ".svn", ".tox", ".venv",
    "__pypackages__", "_build", "buck-out", "build", "dist", "node_modules",
    "venv", ".env", "env", "data", "output",
]
line-length = 88
dummy-variable-rgx = "^(_+|(_+[a-zA-Z0-9_]*[a-zA-Z0-9]+?))$"
target-version = "py310" # Adjust as needed

[tool.ruff.lint.mccabe]
max-complexity = 10

[tool.ruff.lint.isort]
combine-as-imports = true
force-wrap-aliases = true
known-first-party = ["src"] # Tell isort about your source directory

[tool.ruff.lint.flake8-quotes]
docstring-quotes = "double"
inline-quotes = "single"

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ruff.lint.per-file-ignores]
"tests/*" = ["S101"] # Allow assert in tests
"__init__.py" = ["F401"] # Ignore unused imports in __init__ files

# Optional: If using ruff format
# [tool.ruff.format]
# quote-style = "double"
# indent-style = "space"
# skip-magic-trailing-comma = false
# line-ending = "auto"
EOM
)
    # Perform replacements
    PYPROJECT_CONTENT="$PYPROJECT_TEMPLATE"
    PYPROJECT_CONTENT="${PYPROJECT_CONTENT//<PROJ_NAME_PLACEHOLDER>/$NEW_NAME}"
    PYPROJECT_CONTENT="${PYPROJECT_CONTENT//<AUTHOR_NAME_PLACEHOLDER>/$AUTHOR_NAME}"
    PYPROJECT_CONTENT="${PYPROJECT_CONTENT//<AUTHOR_EMAIL_PLACEHOLDER>/$AUTHOR_EMAIL}"

    echo "$PYPROJECT_CONTENT" > pyproject.toml
    green "pyproject.toml created."
fi


if [[ "$SETUP_DOCKER" == "y" ]]; then
    # --- Generate Dockerfile ---
    DOCKERFILE_CONTENT=$(cat <<- EOM
# Base Image - Selected during initialization
FROM ${DOCKER_BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    neofetch \
    tmux \
    wget \
    zsh \
    sudo \
    bat \
    curl \
    rsync \
    git \
    python3-pip \
    unzip \
    tree \
    graphicsmagick \
    ffmpegthumbnailer \
    magic-wormhole \
    # Add any other system dependencies here
    && rm -rf /var/lib/apt/lists/*
EOM
)

    if [[ "$DOCKER_INSTALL_DOTFILES" == "y" ]]; then
        DOCKERFILE_CONTENT+=$(cat <<- EOM

# Install dotfiles (optional)
RUN apt-get update && apt-get install -y --no-install-recommends curl wget git apt-utils \\
    && wget -O - https://raw.githubusercontent.com/bobbydmartino/.dotfiles/main/docker_install.sh | bash \\
    && rm -rf /var/lib/apt/lists/*
EOM
)
    fi

    DOCKERFILE_CONTENT+=$(cat <<- EOM

# Install uv (fast Python package installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:\$PATH"
ENV UV_CACHE_DIR="/root/.cache/uv" # Cache uv downloads

# Set up working directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml* requirements.txt* ./

# Create and activate virtual environment using uv
# Using /opt/venv for convention, change if needed
RUN uv venv /opt/venv --python python3
ENV PATH="/opt/venv/bin:\$PATH"
# Activate venv for subsequent RUN commands (optional, depends on needs)
# SHELL ["/bin/bash", "-c", "source /opt/venv/bin/activate && exec /bin/bash -c \"\$0\" \"\$@\""]

# Install dependencies using uv
# If pyproject.toml exists and has dependencies, it can install from it directly
# Otherwise, falls back to requirements.txt if it exists
RUN if [ -f pyproject.toml ]; then \\
        echo "Installing dependencies from pyproject.toml"; \\
        uv pip install .; \\
    elif [ -f requirements.txt ]; then \\
        echo "Installing dependencies from requirements.txt"; \\
        uv pip install -r requirements.txt; \\
    else \\
        echo "No pyproject.toml or requirements.txt found, skipping dependency installation."; \\
    fi
EOM
)

    # Add user creation logic if requested
    if [[ "$DOCKER_USER_ACCESS" == "y" ]]; then
        DOCKERFILE_CONTENT+=$(cat <<- EOM

# Create non-root user
RUN useradd -ms /bin/zsh ${DOCKER_USERNAME} \\
    && echo "${DOCKER_USERNAME}:${DOCKER_PASSWORD}" | chpasswd \\
    && adduser ${DOCKER_USERNAME} sudo \\
    && echo "${DOCKER_USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers # Optional: Passwordless sudo

# Set up user's working directory and environment
USER ${DOCKER_USERNAME}
WORKDIR /home/${DOCKER_USERNAME}/app
ENV PATH="/home/${DOCKER_USERNAME}/.local/bin:\$PATH"
ENV UV_CACHE_DIR="/home/${DOCKER_USERNAME}/.cache/uv"
# Copy project files as the user
COPY --chown=${DOCKER_USERNAME}:${DOCKER_USERNAME} . /home/${DOCKER_USERNAME}/app
EOM
)
        # Set the entry point for the user
        DOCKERFILE_CONTENT+=$(echo -e "\nENTRYPOINT [\"/bin/zsh\"]")
    else
        # Default root user setup
        DOCKERFILE_CONTENT+=$(cat <<- EOM

# Copy project files as root
COPY . /app

# Set default command/entrypoint for root
WORKDIR /app
ENTRYPOINT ["/bin/zsh"]
EOM
)
    fi

    echo "$DOCKERFILE_CONTENT" > Dockerfile
    green "Dockerfile created."

    # --- Generate docker-compose.yml ---
    COMPOSE_CONTENT=$(cat <<- EOM
version: '3.8' # Use a more modern version

services:
  ${NEW_NAME}: # Service name based on project name
    build:
      context: .
      # Optionally pass build args like UID/GID if needed for permissions
      # args:
      #   USER_ID: \${UID:-1000}
      #   GROUP_ID: \${GID:-1000}
    container_name: ${NEW_NAME}_dev # Explicit container name
    tty: true # Allocate a pseudo-TTY
    stdin_open: true # Keep STDIN open
    stop_grace_period: 1s # Quick stop
    hostname: ${NEW_NAME} # Set hostname inside container
EOM
)

    # Add NVIDIA runtime if selected
    if [[ "$DOCKER_NVIDIA_SUPPORT" == "y" ]]; then
        COMPOSE_CONTENT+=$(cat <<- EOM
    # NVIDIA GPU Configuration
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all # Or specify count like 1, 2
              capabilities: [gpu, utility, compute] # Common capabilities
    # Alternatively, for older docker-compose versions or Docker engines:
    # runtime: nvidia
EOM
)
    fi

    # Add volumes if any were selected
    if [ ${#VOLUMES_TO_MOUNT[@]} -gt 0 ]; then
        COMPOSE_CONTENT+=$(echo -e "\n    volumes:")
        for host_path in "${!VOLUMES_TO_MOUNT[@]}"; do
            container_path="${VOLUMES_TO_MOUNT[$host_path]}"
            # Ensure consistent path separators (use forward slashes)
            host_path_clean=$(echo "$host_path" | sed 's#\\#/#g')
             # Use relative paths from docker-compose.yml location
            COMPOSE_CONTENT+=$(echo -e "      - ./$host_path_clean:${container_path}")
        done
    fi

     # Add common ports (optional) - Example for Jupyter or a web service
    # COMPOSE_CONTENT+=$(cat <<- EOM
    # ports:
    #   - "8888:8888" # Example: Jupyter Notebook host:container
    #   - "8000:8000" # Example: Web service
    # EOM
    #)

     # Add environment variables (optional)
    # COMPOSE_CONTENT+=$(cat <<- EOM
    # environment:
    #   - MY_ENV_VAR=my_value
    #   # - NVIDIA_VISIBLE_DEVICES=all # If using runtime: nvidia
    # EOM
    #)

    echo "$COMPOSE_CONTENT" > docker-compose.yml
    green "docker-compose.yml created."

    # Create .dockerignore
    if [[ ! -f .dockerignore ]]; then
        cat > .dockerignore <<- EOM
# Git files
.git/
.gitignore
.gitattributes

# Docker specific files
Dockerfile
docker-compose.yml
.dockerignore

# Python virtual environment and cache
.venv/
env/
venv/
__pycache__/
*.pyc
*.pyo
*.pyd
.pytest_cache/
.mypy_cache/
.ruff_cache/
.uv_cache/

# Build artifacts
build/
dist/
*.egg-info/
wheels/

# OS specific files
.DS_Store
Thumbs.db

# IDE/Editor files
.vscode/
.idea/
*.swp

# Secrets / Sensitive data (add patterns as needed)
*.env
secrets/

# Data and Output (usually mounted as volumes, not copied)
data/
output/

# Node modules (if applicable)
node_modules/
EOM
        green ".dockerignore created."
    fi
fi

# --- Git Initialization ---
if [[ "$GIT_INIT" == "y" ]]; then
    green "\nInitializing Git repository..."
    git init -b "$BRANCH_NAME" # Initialize and set branch name
    green "Git repository initialized with branch '$BRANCH_NAME'."

    if [ -n "$GIT_REMOTE_URL" ]; then
        git remote add origin "$GIT_REMOTE_URL"
        green "Git remote 'origin' set to: $GIT_REMOTE_URL"
    fi

    # Add all created files
    git add .

    # Check if there's anything to commit
    if git diff-index --quiet HEAD --; then
        yellow "No changes to commit."
    else
        git commit -m "Initial commit: Setup project structure"
        green "Initial commit created."
    fi

    yellow "\nNext steps for Git:"
    if [ -n "$GIT_REMOTE_URL" ]; then
       echo "  - Ensure the remote repository exists: $GIT_REMOTE_URL"
       echo "  - Push the initial commit: git push -u origin $BRANCH_NAME"
    else
       echo "  - Add a remote repository later: git remote add origin <your-repo-url>"
       echo "  - Push the initial commit: git push -u origin $BRANCH_NAME"
    fi
fi

# --- Final Messages ---
green "\n-------------------------------------"
green "Project '$NEW_NAME' initialization complete!"
green "Location: $(pwd)"
yellow "\nSummary of created items:"
[[ "$CREATE_README" == "y" ]] && echo "  - README.md"
[[ "$CREATE_SRC_DIR" == "y" ]] && echo "  - src/"
[[ "$CREATE_DATA_DIR" == "y" ]] && echo "  - data/"
[[ "$CREATE_GITIGNORE" == "y" ]] && echo "  - .gitignore"
[[ "$CREATE_PYPROJECT" == "y" ]] && echo "  - pyproject.toml"
[[ "$CREATE_REQUIREMENTS" == "y" ]] && echo "  - requirements.txt"
if [[ "$SETUP_DOCKER" == "y" ]]; then
    echo "  - Dockerfile (Base: $DOCKER_BASE_IMAGE)"
    echo "  - docker-compose.yml"
    echo "  - .dockerignore"
fi
[[ "$GIT_INIT" == "y" ]] && echo "  - Git repository initialized (Branch: $BRANCH_NAME)"

yellow "\nNext steps:"
echo "  - cd $(pwd)"
[[ "$CREATE_PYPROJECT" == "y" ]] && echo "  - Review and add dependencies to pyproject.toml or requirements.txt"
if [[ "$SETUP_DOCKER" == "y" ]]; then
    echo "  - Build the Docker image: docker compose build"
    echo "  - Start the container: docker compose up -d"
    echo "  - Access the container: docker compose exec $NEW_NAME zsh # or bash"
fi
echo "  - Start coding!"
green "-------------------------------------\n"

exit 0
