#!/bin/bash

# Get the script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Clone the base_repo
git clone https://github.com/bobbydmartino/base_repo.git new_project
cd new_project

# Remove the .git folder to dissociate with the base_repo
rm -rf .git

# Prompt for the new project name
echo "Enter the new repo name:"
read NEW_NAME
mv ../new_project ../$NEW_NAME
cd ../$NEW_NAME


# Functions for creating various files/folders
create_readme() {
    echo "# $NEW_NAME" > README.md
    echo "README.md created."
}

create_dockerfile() {
    touch Dockerfile
    echo "Dockerfile created."
}

create_docker_compose() {
    touch docker-compose.yml
    echo "docker-compose.yml created."
}

create_requirements() {
    touch requirements.txt
    echo "requirements.txt created."
}

create_code_folder() {
    mkdir code
    echo "code/ directory created."
}

create_data_folder() {
    mkdir data
    echo "data/ directory created."
}

# Loop to ask user what they want to create
while true; do
    echo "Choose an option:"
    echo "1. Create README.md"
    echo "2. Create Dockerfile"
    echo "3. Create docker-compose.yml"
    echo "4. Create requirements.txt"
    echo "5. Create code/ directory"
    echo "6. Create data/ directory"
    echo "7. All of the above"
    echo "8. Done"
    read CHOICE

    case $CHOICE in
        1)
        create_readme
        ;;
        2)
        create_dockerfile
        ;;
        3)
        create_docker_compose
        ;;
        4)
        create_requirements
        ;;
        5)
        create_code_folder
        ;;
        6)
        create_data_folder
        ;;
        7)
        create_readme
        create_dockerfile
        create_docker_compose
        create_requirements
        create_code_folder
        create_data_folder
        ;;
        8)
        break
        ;;
        *)
        echo "Invalid option."
        ;;
    esac
done


# Ask if the user wants to initialize the repo
echo "Do you want to git initialize the repo? (yes/no)"
read GIT_INIT

if [ "$GIT_INIT" = "yes" ]; then
    git init
    
    # Ask for branch name
    echo "Branch name (main/master):"
    read BRANCH_NAME
    git checkout -b $BRANCH_NAME

    # Ask for origin
    echo "Enter git origin (or leave blank to skip):"
    read GIT_ORIGIN
    if [ -n "$GIT_ORIGIN" ]; then
        git remote add origin $GIT_ORIGIN
    fi

    # Make an initial commit
    git add .
    git commit -m "Initial commit"
fi


# Check if Dockerfile exists and modify accordingly
if [ -f "Dockerfile" ]; then
    # Default Dockerfile content
    cat > Dockerfile <<- EOM
FROM ubuntu:latest

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        tmux \
        wget \
        zsh \
        sudo \
        curl \
        rsync \
        git \
        unzip \
        python3-pip \
        python-is-python3 \
        python3-venv \
        && rm -rf /var/lib/apt/lists/*
EOM

    # If requirements.txt exists, append to Dockerfile
    if [ -f "requirements.txt" ]; then
        echo "COPY requirements.txt /tmp/requirements.txt" >> Dockerfile
        echo "RUN pip install -r /tmp/requirements.txt" >> Dockerfile
    fi

    # Check for user access
    echo "Do you require user access inside the container? (yes/no)"
    read USER_ACCESS
    if [ "$USER_ACCESS" = "yes" ]; then
        echo "Enter the desired username:"
        read USERNAME
        echo "Enter the desired password:"
        read -s PASSWORD

        echo "RUN useradd -m $USERNAME && echo \"$USERNAME:$PASSWORD\" | chpasswd && adduser $USERNAME sudo" >> Dockerfile
        echo "WORKDIR /home/$USERNAME" >> Dockerfile
    else
        echo "WORKDIR /root/" >> Dockerfile
    fi

    # Set the entrypoint
    echo "ENTRYPOINT [\"/bin/bash\"]" >> Dockerfile

    echo "Dockerfile updated."
fi


# Check if docker-compose.yml exists and modify accordingly
if [ -f "docker-compose.yml" ]; then
    # Base content for docker-compose.yml
    cat > docker-compose.yml <<- EOM
version: '3'
services:
  $NEW_NAME:
    build: .
    tty: true
    stdin_open: true
EOM

    # List of folders to check for mounting as volumes
    FOLDERS=("code" "data") # Add other folders here as needed

    # Iterate over the folders and prompt user
    VOLUMES=()
    for folder in "${FOLDERS[@]}"; do
        if [ -d "$folder" ]; then
            echo "Do you want to mount $folder as a volume? (yes/no)"
            read MOUNT_VOLUME
            if [ "$MOUNT_VOLUME" = "yes" ]; then
                VOLUMES+=("./$folder:/$folder")
            fi
        fi
    done

    # If there are any volumes to add, append them to docker-compose.yml
    if [ ${#VOLUMES[@]} -ne 0 ]; then
        echo "    volumes:" >> docker-compose.yml
        for volume in "${VOLUMES[@]}"; do
            echo "      - $volume" >> docker-compose.yml
        done
    fi

    # Set the hostname
    echo "    hostname: $NEW_NAME" >> docker-compose.yml

    echo "docker-compose.yml updated."
fi


echo "Initialization complete."

