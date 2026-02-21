from typing import Optional, Tuple
import torch
import torch.nn.functional as F
from transformers import AutoTokenizer, AutoModelForSequenceClassification

MODEL_NAME = "cardiffnlp/twitter-roberta-base-sentiment-latest"

class ToneClassifier:
    def __init__(self):
        self.tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
        self.model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME)
        self.model.eval()

        # Model label mapping
        self.labels = ["negative", "neutral", "positive"]

    def classify_tone(
        self,
        text: str,
        volume: Optional[float] = None,
    ) -> Tuple[str, float]:

        # Tokenize text
        inputs = self.tokenizer(
            text,
            return_tensors="pt",
            truncation=True,
            padding=True
        )

        with torch.no_grad():
            outputs = self.model(**inputs)
            probs = F.softmax(outputs.logits, dim=1)[0]

        confidence, predicted_class = torch.max(probs, dim=0)
        tone = self.labels[predicted_class.item()]
        confidence = confidence.item()

        # 🔊 Optional simple prosody fusion
        if volume is not None:
            if volume > 0.7 and tone == "negative":
                tone = "angry"
                confidence = min(1.0, confidence + 0.1)
            elif volume < 0.2 and tone == "negative":
                tone = "sad"
                confidence = min(1.0, confidence + 0.1)

        return tone, float(confidence)