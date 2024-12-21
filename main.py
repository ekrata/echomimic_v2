import os

import aiofiles
import boto3
import ffmpeg
from botocore.exceptions import NoCredentialsError, PartialCredentialsError
from fastapi import Depends, FastAPI, File, UploadFile
from fastapi.responses import BackgroundTasks, JSONResponse
from infer import main
from pydantic import BaseModel

app = FastAPI()


@app.get("/")
def read_root():
    return {"Hello": "World"}


class ModelParams(BaseModel):
    config: str = "./configs/prompts/infer.yaml"
    W: int = 768
    H: int = 768
    L: int = 240
    seed: int = 3407
    context_frames: int = 12
    context_overlap: int = 3
    cfg: float = 2.5
    steps: int = 30
    sample_rate: int = 16000
    fps: int = 24
    device: str = "cuda"
    ref_images_dir: str = "./assets/halfbody_demo/refimag"
    audio_dir: str = "./assets/halfbody_demo/audio"
    pose_dir: str = "./assets/halfbody_demo/pose"
    refimg_name: str = "custom/avatar.png"
    audio_name: str = "echomimicv2_woman.wav"
    pose_name: str = "01"
    language: str = "english"
    output_style: str = "english"
    source_video_1_name: str = "source_video_1.mp4"
    brand_id: str
    video_id: str


@app.post("/start_generation/{video_id}")
async def start_generation(
    background_tasks: BackgroundTasks,
    params: ModelParams = Depends(),
    refimg: UploadFile = File(description="A file with PNG/JPEG image format"),
    audio: UploadFile = File(description="A file with WAV audio format"),
    source_video_1: UploadFile = File(
        default=None,
        description="A existing video to be used with the generated avatar",
    ),
):
    """
    Endpoint to process request with given query parameters.
    """

    config = params.config
    W = params.W
    H = params.H
    L = params.L
    seed = params.seed
    context_frames = params.context_frames
    context_overlap = params.context_overlap
    cfg = params.cfg
    steps = params.steps
    sample_rate = params.sample_rate
    fps = params.fps
    device = params.device
    ref_images_dir = params.ref_images_dir
    audio_dir = params.audio_dir
    pose_dir = params.pose_dir
    refimg_name = params.refimg_name
    audio_name = params.audio_name
    pose_name = params.pose_name
    language = params.language
    output_style = params.output_style
    source_video_1_name = params.source_video_1_name
    brand_id = params.brand_id
    video_id = params.video_id

    if refimg.content_type not in ["image/png", "image/jpeg"]:
        return JSONResponse(
            content={"error": "Invalid image file type"}, status_code=400
        )

    if audio.content_type != "audio/wav":
        return JSONResponse(
            content={"error": "Invalid audio file type"}, status_code=400
        )
    if source_video_1.content not in ["video/mp4", "video/webm"]:
        return JSONResponse(
            content={"error": "Invalid audio file type"}, status_code=400
        )

    # write params so can be accessed by infer script
    async with aiofiles.open("custom/avatar.png", "wb") as out_file:
        content = await refimg.read()  # async read
        await out_file.write(content)  # async write

    async with aiofiles.open(f"{language}/${audio_name}", "wb") as out_file:
        content = await audio.read()  # async read
        await out_file.write(content)  # async write

    async with aiofiles.open(source_video_1_name, "wb") as out_file:
        content = await source_video_1.read()  # async read
        await out_file.write(content)  # async write

    args = {
        "config": config,
        "W": W,
        "H": H,
        "L": L,
        "seed": seed,
        "context_frames": context_frames,
        "context_overlap": context_overlap,
        "cfg": cfg,
        "steps": steps,
        "sample_rate": sample_rate,
        "fps": fps,
        "device": device,
        "ref_images_dir": ref_images_dir,
        "audio_dir": audio_dir,
        "pose_dir": pose_dir,
        "refimg_name": refimg_name,
        "audio_name": audio_name,
        "pose_name": pose_name,
        "refimg": refimg,
        "source_video_1": source_video_1,
        "source_video_1_name": source_video_1_name,
        "output_style": output_style,
        "audio": audio,
        "brand_id": brand_id,
    }

    background_tasks.add_task(generate_video, args)
    return JSONResponse(status_code=202, content={"message": "Processing has started."})


def horizontal_split(input1, input2, output):
    (
        ffmpeg.input(input1)
        .output(input2)
        .filter("hstack")
        .output(output, **{"c:v": "h264_nvenc", "preset": "fast", "rc-lookahead": "32"})
        .run(raise_on_error=True)
    )


def overlay_video(background, overlay, output):
    (
        ffmpeg.input(background)
        .filter("scale2ref", background, overlay)
        .output(overlay)
        .filter("overlay")
        .output(output, **{"c:v": "h264_nvenc", "preset": "fast", "rc-lookahead": "32"})
        .run(raise_on_error=True)
    )


def generate_video(args: ModelParams):
    video_name = main(args)

    final_name = video_name
    if args.output_style == "horizontalSplit":
        horizontal_split("video1.mp4", "video2.mp4", final_name)
    if args.output_style == "overlay_video":
        overlay_video("background.mp4", "overlay.mp4", final_name)

    upload_file_to_s3(
        final_name, os.getenv("BucketName"), f"{args.brand_id}/{args.video_id}"
    )


def upload_file_to_s3(file_name, bucket, object_key):
    # Create an S3 client
    s3_client = boto3.client("s3")

    try:
        s3_client.upload_file(file_name, bucket, object_key)
        print(f"File {file_name} uploaded to {bucket}/{object_key} successfully.")
    except FileNotFoundError:
        print(f"File {file_name} not found.")
    except NoCredentialsError:
        print("Credentials not available.")
    except PartialCredentialsError:
        print("Incomplete credentials provided.")
