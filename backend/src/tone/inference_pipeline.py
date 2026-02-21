from transformers import AutoProcessor, AutoModelForSequenceClassification
import torch
import numpy as np

MODEL_PATH = "./wav2vec_finetuned"

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

processor = AutoProcessor.from_pretrained(MODEL_PATH)
model = AutoModelForSequenceClassification.from_pretrained(MODEL_PATH)

model.to(device)
model.eval()

def predict(audio_array, sr=16000):
    inputs = processor(
        audio_array,
        sampling_rate=sr,
        return_tensors="pt",
        padding=True
    )

    inputs = {k: v.to(device) for k, v in inputs.items()}

    with torch.no_grad():
        logits = model(**inputs).logits

    probs = torch.softmax(logits, dim=-1)
    confidence, pred = torch.max(probs, dim=-1)

    label = model.config.id2label[pred.item()]

    return label, confidence.item()