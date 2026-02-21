import torchaudio

SAMPLE_RATE = 16000

def load_and_resample(path):
    waveform, sr = torchaudio.load(path)

    if sr != SAMPLE_RATE:
        waveform = torchaudio.transforms.Resample(sr, SAMPLE_RATE)(waveform)

    return waveform.squeeze()