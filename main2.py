import cv2
import numpy as np
import time
from fastapi import FastAPI, File, UploadFile
import uvicorn
import tensorflow.lite as tflite
from collections import deque, Counter

app = FastAPI()

# Load TFLite model
interpreter = tflite.Interpreter(model_path="./assets/models/1.tflite")
interpreter.allocate_tensors()

# Get input and output details
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

# Mapping class index to letters (Modify based on your model's class mapping)
class_to_letter = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 
    'P', 'Q', 'R', 'S', ' ', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
]

# Global variables
sentence = ""
detections_queue = deque()  # Stores (timestamp, letter, confidence)

def preprocess_image(image):
    """Prepares the image for TFLite model input (Resize, Normalize)."""
    image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)  # Convert to RGB
    image = cv2.resize(image, (input_details[0]['shape'][1], input_details[0]['shape'][2]))  # Resize
    image = np.array(image, dtype=np.float32) / 255.0  # Normalize to [0,1]
    image = np.expand_dims(image, axis=0)  # Add batch dimension
    return image

def detect_objects(image):
    """Runs the TFLite model and extracts the most confident class."""
    input_tensor = preprocess_image(image)
    
    interpreter.set_tensor(input_details[0]['index'], input_tensor)
    interpreter.invoke()
    
    output_data = interpreter.get_tensor(output_details[0]['index'])  # Get output probabilities
    
    class_index = np.argmax(output_data)  # Get class index with highest probability
    confidence = np.max(output_data)  # Get confidence score
    
    letter = class_to_letter[class_index] if class_index < len(class_to_letter) else "?"
    return letter, confidence

@app.post("/process_frame")
async def process_frame(frame: UploadFile = File(...)):
    """Receives a frame, detects the best letter, and updates the sentence."""
    global sentence, detections_queue

    contents = await frame.read()
    np_image = np.frombuffer(contents, np.uint8)
    image = cv2.imdecode(np_image, cv2.IMREAD_COLOR)

    letter, confidence = detect_objects(image)
    current_time = time.time()

    # Store detection in queue (timestamp, letter, confidence)
    detections_queue.append((current_time, letter, confidence))

    # Remove old detections (older than 3 seconds)
    while detections_queue and (current_time - detections_queue[0][0] > 3):
        detections_queue.popleft()

    # Find most frequent letter in the last 3 seconds
    if detections_queue:
        letter_counts = Counter([item[1] for item in detections_queue])
        best_letter = max(letter_counts.keys(), key=lambda l: (letter_counts[l], 
                      max(conf for t, lt, conf in detections_queue if lt == l)))

        # Avoid duplicate consecutive letters
        if not sentence or best_letter != sentence[-1] or (len(sentence) > 1 and best_letter == sentence[-2]):
            sentence += best_letter
        print(sentence)
        return {"detected_letter": best_letter, "updated_sentence": sentence}

@app.post("/finish_record")
async def finish_record():
    """Returns the final detected sentence."""
    global sentence
    return {"final_sentence": sentence}

@app.post("/reset_sentence")
async def reset_sentence():
    """Resets the detected sentence and clears history."""
    global sentence, detections_queue
    sentence = ""
    detections_queue.clear()
    return {"message": "Sentence reset successfully"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
