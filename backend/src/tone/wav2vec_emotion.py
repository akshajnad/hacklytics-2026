import torch
import numpy as np
import os
from transformers import Wav2Vec2Processor, Wav2Vec2ForSequenceClassification

MODEL_PATH = os.path.join(
    os.path.dirname(__file__),
    "wav2vec_finetuned"
)

class Wav2VecEmotion:
    def __init__(self, device=None):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")

        print(f"Loading fine-tuned Wav2Vec2 model on {self.device}...")

        self.processor = Wav2Vec2Processor.from_pretrained(MODEL_PATH)
        self.model = Wav2Vec2ForSequenceClassification.from_pretrained(MODEL_PATH)

        self.model.to(self.device)
        self.model.eval()

        self.labels = np.load(
            os.path.join(MODEL_PATH, "label_classes.npy"),
            allow_pickle=True
        )

    def predict(self, audio_waveform: np.ndarray, sample_rate: int = 16000):

        if len(audio_waveform) < sample_rate:
            return "neutral", 0.0

        inputs = self.processor(
            audio_waveform,
            sampling_rate=sample_rate,
            return_tensors="pt",
            padding=True,
        )

        inputs = {k: v.to(self.device) for k, v in inputs.items()}

        with torch.no_grad():
            logits = self.model(**inputs).logits

        probs = torch.softmax(logits, dim=-1)
        confidence, predicted_id = torch.max(probs, dim=-1)

        label = self.labels[predicted_id.item()]

        return label, confidence.item()