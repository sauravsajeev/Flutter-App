import cv2
import numpy as np
import time
from fastapi import FastAPI, File, UploadFile
import uvicorn
from ultralytics import YOLO
from collections import deque, Counter
from symspellpy import SymSpell, Verbosity

# Load SymSpell dictionary
sym_spell = SymSpell(max_dictionary_edit_distance=2, prefix_length=7)
sym_spell.load_dictionary("frequency_dictionary_en_82_765.txt", term_index=0, count_index=1)

def correct_sentence(sentence):
    words = sentence.split()
    corrected_words = [sym_spell.lookup(word, Verbosity.CLOSEST, max_edit_distance=2)[0].term if sym_spell.lookup(word, Verbosity.CLOSEST, max_edit_distance=2) else word for word in words]
    return " ".join(corrected_words)

app = FastAPI()

# Load YOLOv8 model (Use your trained model)
model = YOLO("./model_unquant.pt")  # Change path if needed

# List for class index to letter mapping
class_to_letter = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 
    'P', 'Q', 'R', 'S',' ', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
]

# Global variables
sentence = ""
detections_queue = deque()  # Stores (timestamp, letter, confidence)

def detect_objects(image):
    """Run YOLOv8 model and extract class index and confidence."""
    results = model(image)
    
    detections = []
    for result in results:
        class_ids = result.boxes.cls.cpu().numpy().astype(int)  # Class indices
        confidences = result.boxes.conf.cpu().numpy()  # Confidence scores
        
        for i in range(len(class_ids)):
            if confidences[i] >= 0.7:  # Only consider confidence > 70%
                letter = class_to_letter[class_ids[i]] if 0 <= class_ids[i] < len(class_to_letter) else "?"
                detections.append((letter, confidences[i]))  # Store letter and confidence
    
    return detections

@app.post("/process_frame")
async def process_frame(frame: UploadFile = File(...)):
    """Receives a frame, runs YOLOv8 detection, selects the best letter, and updates the sentence."""
    global sentence, detections_queue

    contents = await frame.read()
    np_image = np.frombuffer(contents, np.uint8)
    image = cv2.imdecode(np_image, cv2.IMREAD_COLOR)

    detected_objects = detect_objects(image)

    current_time = time.time()
    
    # Add new detections with timestamp
    for letter, confidence in detected_objects:
        detections_queue.append((current_time, letter, confidence))

    # Remove old detections (older than 4 seconds)
    while detections_queue and (current_time - detections_queue[0][0] > 4):
        detections_queue.popleft()

    # Find the best letter in the last 3 seconds
    if detections_queue:
        letter_counts = Counter([item[1] for item in detections_queue])
        best_letter = max(letter_counts.keys(), key=lambda l: (letter_counts[l], 
                      max(conf for t, lt, conf in detections_queue if lt == l)))

        # Ensure letters are not repeated unless they are consecutive
        if not sentence or best_letter != sentence[-1] or (len(sentence) > 1 and best_letter == sentence[-2]):
            sentence += best_letter
        return best_letter

@app.post("/finish_record")
async def finish_record():
    global sentence
    corrected_sentence = correct_sentence(sentence)
    return corrected_sentence.replace('"', '') if len(sentence) > 6 else sentence.replace('"', '')

@app.post("/reset_sentence")
async def reset_sentence():
    """Reset the detected sentence and clear history."""
    global sentence, detections_queue
    sentence = ""
    detections_queue.clear()
    return {"message": "Sentence reset successfully"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
