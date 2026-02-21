import os
import pandas as pd
from sklearn.model_selection import train_test_split

BASE_DIR = os.path.dirname(__file__)
RAVDESS_DIR = os.path.join(BASE_DIR, "ravdess")

emotion_map = {
    "01": "neutral",
    "02": "calm",
    "03": "happy",
    "04": "sad",
    "05": "angry",
    "06": "fearful",
    "07": "disgust",
    "08": "surprised"
}

rows = []

for actor in os.listdir(RAVDESS_DIR):
    actor_path = os.path.join(RAVDESS_DIR, actor)
    if not os.path.isdir(actor_path):
        continue

    for file in os.listdir(actor_path):
        if file.endswith(".wav"):
            parts = file.split("-")
            emotion_code = parts[2]

            if emotion_code in emotion_map:
                label = emotion_map[emotion_code]
                full_path = os.path.join(actor_path, file)

                rows.append({
                    "path": full_path,
                    "label": label
                })

df = pd.DataFrame(rows)

train_df, val_df = train_test_split(
    df,
    test_size=0.2,
    stratify=df["label"],
    random_state=42
)

data_dir = os.path.join(BASE_DIR, "data")
os.makedirs(data_dir, exist_ok=True)

train_df.to_csv(os.path.join(data_dir, "train.csv"), index=False)
val_df.to_csv(os.path.join(data_dir, "val.csv"), index=False)

print("Dataset prepared!")
print("Train samples:", len(train_df))
print("Validation samples:", len(val_df))