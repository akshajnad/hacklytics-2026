import os
import numpy as np
import pandas as pd
import torch
from datasets import Dataset
from sklearn.preprocessing import LabelEncoder
from transformers import (
    Wav2Vec2Processor,
    Wav2Vec2ForSequenceClassification,
    TrainingArguments,
    Trainer
)
from dataset_utils import load_and_resample

MODEL_NAME = "superb/wav2vec2-base-superb-er"
SAMPLE_RATE = 16000

BASE_DIR = os.path.dirname(__file__)
DATA_DIR = os.path.join(BASE_DIR, "data")
OUTPUT_DIR = os.path.join(BASE_DIR, "wav2vec_finetuned")

train_df = pd.read_csv(os.path.join(DATA_DIR, "train.csv"))
val_df = pd.read_csv(os.path.join(DATA_DIR, "val.csv"))

label_encoder = LabelEncoder()
train_df["label"] = label_encoder.fit_transform(train_df["label"])
val_df["label"] = label_encoder.transform(val_df["label"])

num_labels = len(label_encoder.classes_)

processor = Wav2Vec2Processor.from_pretrained(MODEL_NAME)

def preprocess(example):
    waveform = load_and_resample(example["path"])

    example["input_values"] = processor(
        waveform.numpy(),
        sampling_rate=SAMPLE_RATE
    ).input_values[0]

    return example

train_dataset = Dataset.from_pandas(train_df)
val_dataset = Dataset.from_pandas(val_df)

train_dataset = train_dataset.map(preprocess)
val_dataset = val_dataset.map(preprocess)

train_dataset = train_dataset.remove_columns(["path"])
val_dataset = val_dataset.remove_columns(["path"])

model = Wav2Vec2ForSequenceClassification.from_pretrained(
    MODEL_NAME,
    num_labels=num_labels
)

training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    evaluation_strategy="epoch",
    save_strategy="epoch",
    learning_rate=2e-5,
    per_device_train_batch_size=4,
    per_device_eval_batch_size=4,
    num_train_epochs=5,
    weight_decay=0.01,
    logging_steps=10,
    load_best_model_at_end=True,
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=train_dataset,
    eval_dataset=val_dataset,
)

trainer.train()

model.save_pretrained(OUTPUT_DIR)
processor.save_pretrained(OUTPUT_DIR)

np.save(os.path.join(OUTPUT_DIR, "label_classes.npy"), label_encoder.classes_)

print("Training complete. Model saved to:", OUTPUT_DIR)