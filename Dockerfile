# Start with a base image
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p $HOME/miniconda && \
    rm miniconda.sh

# Add Miniconda to PATH
ENV PATH="$HOME/miniconda/bin:$PATH"

# Initialize conda
RUN conda init bash

# Clone the repository and navigate into it
RUN git clone https://github.com/antgroup/echomimic_v2 && cd echomimic_v2

# Create and activate the 'echomimic' conda environment
RUN conda create -n echomimic python=3.10 -y && \
    /bin/bash -c "source activate echomimic && \
    pip install pip -U && \
    pip install torch==2.0.1 torchvision==0.20.1 torchaudio==2.0.1 xformers==0.0.28.post3 --index-url https://download.pytorch.org/whl/cu124 && \
    pip install torchao --index-url https://download.pytorch.org/whl/nightly/cu124 && \
    pip install -r echomimic_v2/requirements.txt && \
    pip install --no-deps facenet_pytorch==2.6.0 && \
    git lfs install && \
    git clone https://huggingface.co/BadToBest/EchoMimicV2 echomimic_v2/pretrained_weights"

# Set the default command to activate the conda environment
CMD ["/bin/bash", "-c", "source activate echomimic && bash"]

### Notes:
# 1. **Base Image**: Uses `ubuntu:22.04` as the base image. Adjust the version as needed.
# 2. **Environment Setup**: Sets up Miniconda, initializes it, and adds it to the path.
# 3. **Repository Setup**: Clones the specified GitHub repository.
# 4. **Conda Environment**: Creates and activates a conda environment named `echomimic`.
# 5. **Python Packages**: Installs specified Python packages and handles pre-trained weights.
# 6. **File Cleanup**: Reduces Docker image size by removing any interim files where possible.
# 7. **Entry Command**: Sets the shell to start in an activated conda environment.

# Before building this Dockerfile, ensure your application’s dependency versions match those available with your selection, especially for PyTorch, as those links and versions may change over time.