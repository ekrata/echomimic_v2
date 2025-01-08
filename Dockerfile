# Use an appropriate Python base image
FROM python:3.12-slim

# Install dependencies and utilities (wget, git, ffmpeg)
RUN apt-get update && apt-get install -y \
    wget \
    git \
    ffmpeg \
    xz-utils \
    && apt-get clean

# Set working directory
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Upgrade pip
RUN pip install --upgrade pip

# Install Python dependencies from requirements.txt
RUN pip install -r requirements.txt

# Install specific versions of torch and other dependencies
RUN pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 xformers==0.0.28.post3 --index-url https://download.pytorch.org/whl/cu124
RUN pip install torchao --index-url https://download.pytorch.org/whl/nightly/cu124
RUN pip install --no-deps facenet_pytorch==2.6.0

# Set up FFmpeg
RUN if [ ! -d "ffmpeg-4.4-amd64-static" ]; then \
        wget https://www.johnvansickle.com/ffmpeg/old-releases/ffmpeg-4.4-amd64-static.tar.xz && \
        tar -xvf ffmpeg-4.4-amd64-static.tar.xz; \
    fi

# Set FFmpeg path environment variable
ENV FFMPEG_PATH /app/ffmpeg-4.4-amd64-static

# Set up Git LFS
RUN git lfs install

# Clone pretrained weights repository if not already done
RUN if [ ! -d "pretrained_weights" ]; then \
        git clone https://huggingface.co/BadToBest/EchoMimicV2 pretrained_weights; \
    fi

# Clone additional repositories
RUN mkdir -p ./pretrained_weights/sd-vae-ft-mse && \
    if [ -z "$(ls -A ./pretrained_weights/sd-vae-ft-mse)" ]; then \
        git clone https://huggingface.co/stabilityai/sd-vae-ft-mse ./pretrained_weights/sd-vae-ft-mse; \
    fi

RUN mkdir -p ./pretrained_weights/sd-image-variations-diffusers && \
    if [ -z "$(ls -A ./pretrained_weights/sd-image-variations-diffusers)" ]; then \
        git clone https://huggingface.co/lambdalabs/sd-image-variations-diffusers ./pretrained_weights/sd-image-variations-diffusers; \
    fi

# Verify required model files in pretrained_weights
RUN if [ ! -f "./pretrained_weights/denoising_unet.pth" ]; then \
        echo "Missing file: denoising_unet.pth"; exit 1; \
    fi && \
    if [ ! -f "./pretrained_weights/reference_unet.pth" ]; then \
        echo "Missing file: reference_unet.pth"; exit 1; \
    fi && \
    if [ ! -f "./pretrained_weights/motion_module.pth" ]; then \
        echo "Missing file: motion_module.pth"; exit 1; \
    fi && \
    if [ ! -f "./pretrained_weights/pose_encoder.pth" ]; then \
        echo "Missing file: pose_encoder.pth"; exit 1; \
    fi

# Set up audio processor and download tiny.pt model
RUN AUDIO_PROCESSOR_DIR="./pretrained_weights/audio_processor" && \
    mkdir -p "$AUDIO_PROCESSOR_DIR" && \
    cd "$AUDIO_PROCESSOR_DIR" && \
    if [ ! -f "tiny.pt" ]; then \
        wget https://openaipublic.azureedge.net/main/whisper/models/65147644a518d12f04e32d6f3b26facc3f8dd46e5390956a9424a650c0ce22b9/tiny.pt; \
    fi && \
    cd ../../..

# Final message
RUN echo "Setup complete!"
