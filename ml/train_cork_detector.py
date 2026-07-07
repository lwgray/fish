import os
import json
import random
from pathlib import Path

import tensorflow as tf
import keras
import keras_cv
from keras_cv import bounding_box

BOX_FORMAT = "xywh"
CLASS_NAMES = ["cork"]
CLASS_TO_ID = {name: i for i, name in enumerate(CLASS_NAMES)}
IMAGE_SIZE = (320, 320)
BATCH_SIZE = 8
EPOCHS = 25
VAL_SPLIT = 0.2
SEED = 42
MAX_BOXES = 8

DATASET_DIR = Path(os.environ.get("CORK_DATASET_DIR", "./dataset"))
OUTPUT_DIR = Path(os.environ.get("CORK_OUTPUT_DIR", "./artifacts"))
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def load_manifest():
    manifest_path = DATASET_DIR / "annotations.json"
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    items = []
    for row in manifest["images"]:
        img_path = DATASET_DIR / "images" / row["file_name"]
        boxes = []
        classes = []
        for b in row.get("boxes", []):
            cls = b.get("class", "cork")
            if cls not in CLASS_TO_ID:
                continue
            boxes.append([float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"])])
            classes.append(float(CLASS_TO_ID[cls]))
        items.append((str(img_path), boxes, classes))
    return items


def decode_image(path):
    bytes_ = tf.io.read_file(path)
    image = tf.image.decode_jpeg(bytes_, channels=3)
    return tf.cast(image, tf.float32)


def load_record(path, boxes, classes):
    image = decode_image(path)
    return {
        "images": image,
        "bounding_boxes": {
            "boxes": boxes,
            "classes": tf.cast(classes, tf.float32),
        },
    }


def build_dataset(records, training=True):
    paths = tf.ragged.constant([r[0] for r in records])
    boxes = tf.ragged.constant([r[1] for r in records], dtype=tf.float32)
    classes = tf.ragged.constant([r[2] for r in records], dtype=tf.float32)

    ds = tf.data.Dataset.from_tensor_slices((paths, boxes, classes))
    ds = ds.map(load_record, num_parallel_calls=tf.data.AUTOTUNE)

    if training:
        augmenter = keras.Sequential([
            keras_cv.layers.RandomFlip(mode="horizontal", bounding_box_format=BOX_FORMAT),
            keras_cv.layers.JitteredResize(
                target_size=IMAGE_SIZE,
                scale_factor=(0.8, 1.2),
                bounding_box_format=BOX_FORMAT,
            ),
        ])
        ds = ds.shuffle(len(records), seed=SEED)
        ds = ds.ragged_batch(BATCH_SIZE, drop_remainder=False)
        ds = ds.map(augmenter, num_parallel_calls=tf.data.AUTOTUNE)
    else:
        resize = keras_cv.layers.Resizing(
            IMAGE_SIZE[0],
            IMAGE_SIZE[1],
            pad_to_aspect_ratio=True,
            bounding_box_format=BOX_FORMAT,
        )
        ds = ds.ragged_batch(BATCH_SIZE, drop_remainder=False)
        ds = ds.map(resize, num_parallel_calls=tf.data.AUTOTUNE)

    def to_tuple(inputs):
        dense_boxes = bounding_box.to_dense(inputs["bounding_boxes"], max_boxes=MAX_BOXES)
        return inputs["images"], dense_boxes

    ds = ds.map(to_tuple, num_parallel_calls=tf.data.AUTOTUNE)
    return ds.prefetch(tf.data.AUTOTUNE)


def main():
    records = load_manifest()
    if not records:
        raise ValueError("No training records found in annotations.json")

    random.Random(SEED).shuffle(records)
    split_idx = max(1, int(len(records) * (1.0 - VAL_SPLIT)))
    train_records = records[:split_idx]
    val_records = records[split_idx:]
    if not val_records:
        val_records = train_records[:1]

    train_ds = build_dataset(train_records, training=True)
    val_ds = build_dataset(val_records, training=False)

    backbone = keras_cv.models.YOLOV8Backbone.from_preset("yolo_v8_xs_backbone_coco")
    model = keras_cv.models.YOLOV8Detector(
        num_classes=len(CLASS_NAMES),
        bounding_box_format=BOX_FORMAT,
        backbone=backbone,
        fpn_depth=1,
    )

    model.prediction_decoder = keras_cv.layers.NonMaxSuppression(
        bounding_box_format=BOX_FORMAT,
        from_logits=False,
        confidence_threshold=0.25,
        iou_threshold=0.5,
    )

    optimizer = keras.optimizers.Adam(
        learning_rate=1e-3,
        global_clipnorm=10.0,
    )

    model.compile(
        optimizer=optimizer,
        classification_loss="binary_crossentropy",
        box_loss="ciou",
    )

    callbacks = [
        keras.callbacks.ModelCheckpoint(
            filepath=str(OUTPUT_DIR / "cork_detector.keras"),
            monitor="val_loss",
            save_best_only=True,
        ),
        keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=5,
            restore_best_weights=True,
        ),
    ]

    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS,
        callbacks=callbacks,
    )

    model.save(OUTPUT_DIR / "cork_detector_final.keras")

    try:
        import tensorflowjs as tfjs
        tfjs.converters.save_keras_model(model, str(OUTPUT_DIR / "tfjs_model"))
        print("Saved TensorFlow.js model to", OUTPUT_DIR / "tfjs_model")
    except Exception as exc:
        print("TensorFlow.js export skipped:", exc)
        print("You can also run: tensorflowjs_converter --input_format=keras cork_detector_final.keras tfjs_model")


if __name__ == "__main__":
    main()
