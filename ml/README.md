# Cork detector end-to-end example

This example shows a full pipeline for training a one-class cork detector in KerasCV and using it in a browser with TensorFlow.js.

## 1. Extract frames

```bash
python python/extract_frames.py /path/to/fishing-video.mp4 --fps 2 --out dataset/images
```

A low starting rate like 1-3 FPS is usually enough for labeling because adjacent frames from fishing footage are highly redundant.

## 2. Create annotation template

```bash
python python/make_annotations_template.py
```

This writes `dataset/annotations.json`. Fill in the `boxes` list for each image where the cork is visible.

### Annotation format

```json
{
  "images": [
    {
      "file_name": "frame_000001.jpg",
      "width": 1920,
      "height": 1080,
      "boxes": [
        {"x": 920, "y": 410, "w": 36, "h": 52, "class": "cork"}
      ]
    }
  ]
}
```

Coordinates use pixel-space `xywh`, which matches the training script configuration. KerasCV requires a consistent declared bounding-box format throughout the pipeline. [page:1]

## 3. Train the model

Install the core packages:

```bash
pip install tensorflow keras keras-cv tensorflowjs pillow
```

Then run:

```bash
export CORK_DATASET_DIR=./dataset
export CORK_OUTPUT_DIR=./artifacts
python python/train_cork_detector.py
```

The training script uses a KerasCV YOLOv8 detector, bounding-box-aware augmentation, and best-model checkpointing. KerasCV’s YOLOv8 example uses this general recipe: `tf.data` input pipeline, ragged boxes, augmentation, detector compile, and fit. [page:1]

## 4. Convert for browser use

The training script tries direct TensorFlow.js export with `tensorflowjs`. If that fails, convert manually:

```bash
tensorflowjs_converter --input_format=keras ./artifacts/cork_detector_final.keras ./web/tfjs_model
```

TensorFlow.js documents two standard routes: use `tensorflowjs_converter` on a saved Keras model, or export directly from Python with the TensorFlow.js converter API. [page:2]

## 5. Run the demo

Serve the folder with any local web server, then open `web/index.html` in a browser.

```bash
cd web
python -m http.server 8000
```

Load the model URL, choose a local video file, and press play. TensorFlow.js loads the model from `model.json`, which references the sharded weight files in the same folder. [page:2]

## Notes

- Use at least a few hundred labeled frames if the cork is tiny or lighting varies a lot.
- Include negative frames with no visible cork to reduce false positives.
- If the cork is extremely small, crop training data to the water region or tile the frame.
- The browser app runs detection on resized frames, then smooths center and size over time to stabilize the zoom window.
- Depending on your exported model signature, you may need to adjust the output parsing block in `web/index.html`.

## Why this design

A detector finds the cork in each sampled frame, while lightweight temporal smoothing handles follow behavior more robustly than forcing the network to learn zoom control directly. TensorFlow.js supports loading converted Keras models in the browser from a `model.json` entry point, which is what the demo expects. [page:2]
