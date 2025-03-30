import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:wakelock/wakelock.dart';
import '../../presentation/widgets/loading.dart';
import 'package:logger/logger.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

final logger = Logger();

class YoloVideo extends StatefulWidget {
  const YoloVideo({Key? key}) : super(key: key);

  @override
  State<YoloVideo> createState() => _YoloVideoState();
}

class _YoloVideoState extends State<YoloVideo> {
  late CameraController controller;
  late List<Map<String, dynamic>> yoloResults;
  late List<CameraDescription> cameras;

  FlutterVision vision = FlutterVision();
  final FlutterTts _flutterTts = FlutterTts();

  CameraImage? cameraImage;
  bool isLoaded = false;
  bool isDetecting = false;

  String recognizedLabel = '';
  String acceptedWord = ''; // To store the formed word
  Map<String, int> detectionStability = {};
  static const int stabilityThreshold = 4; // Frames required for steady detection
  static const int maxDetections = 5; // Limit the number of detections
  Timer? _detectionTimer;
  DateTime? _lastDetectionTime;
  static const int detectionTimeout = 3000;
  List<String> wordSuggestions = []; //for word suggestion
  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    init();
    initTTS();
  }

  init() async {
    cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller.initialize().then((value) {
      if (!mounted) {
        return;
      } else {
        loadModel().then((value) {
          setState(() {
            isLoaded = true;
            isDetecting = false;
            yoloResults = [];
          });
        });
      }
    });
  }

  void initTTS() {
    _flutterTts.getVoices.then((data) {
      try {
        var voices = List<Map>.from(data);
        setState(() {
          voices = voices.where((voice) => voice["name"].contains("en")).toList();
          _flutterTts.setVoice({"name": voices.first["name"], "locale": voices.first["locale"]});
        });
      } catch (e) {
        print(e.toString());
      }
    });
  }

  @override
  void dispose() {
    Wakelock.disable();
    controller.dispose();
    _detectionTimer?.cancel();
    super.dispose();
  }

  Future<void> loadModel() async {
    try {
      await vision.loadYoloModel(
        labels: 'assets/models/labels.txt',
        modelPath: 'assets/models/model_unquant.tflite',
        modelVersion: 'yolov8',
        numThreads: 1,
      );
      setState(() {
        isLoaded = true;
      });
    } on Exception catch (e) {
      logger.e(e.toString());
    }
  }

  // Future<void> objectDetection(CameraImage cameraImage) async {
  //   final result = await vision.yoloOnFrame(
  //     bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
  //     imageHeight: cameraImage.height,
  //     imageWidth: cameraImage.width,
  //     iouThreshold: 0.25,
  //     confThreshold: 0.25,
  //     classThreshold: 0.5,
  //   );

  //   if (result.isNotEmpty) {
  //     setState(() {
  //       yoloResults = result.take(maxDetections).toList(); // Limit detections
  //       logger.i(yoloResults);
  //       for (var detection in yoloResults) {
  //         String label = detection['tag'];
  //         detectionStability[label] = (detectionStability[label] ?? 0) + 1;
  //          logger.i(detectionStability[label]);
  //          if (detectionStability[label]! >= stabilityThreshold) {
  //           recognizedLabel += label;
  //            logger.i(recognizedLabel);
  //           if ((detection['box'][4] * 100) >= 80) {
  //             acceptedWord += recognizedLabel;
  //           }
  //         }
  //       }

  //       //detectionStability.removeWhere((key, value) => value < stabilityThreshold);
  //     });
  //   }
  // }
void _resetDetectionTimer() {
  _detectionTimer?.cancel();
  _detectionTimer = Timer(Duration(milliseconds: detectionTimeout), () {
    setState(() {
      yoloResults.clear();
      _lastDetectionTime = null;
    });
  });
}

Future<List<String>> fetchGoogleSuggestions(String query) async {
  final url = Uri.parse(
      'https://suggestqueries.google.com/complete/search?client=firefox&q=$query');

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return List<String>.from(data[1]); // The suggestions are at index 1
  } else {
    throw Exception('Failed to fetch suggestions: ${response.body}');
  }
}
Future<void> updateSuggestions() async {
  if (recognizedLabel.isNotEmpty) {
    try {
      wordSuggestions = await fetchGoogleSuggestions(recognizedLabel);
      List<String> filteredSuggestions = [];
      for (String word in wordSuggestions){
      if (!word.contains(' ')) {
               filteredSuggestions.add(word);
      }}
      wordSuggestions = filteredSuggestions;
      logger.i("word suggestion: $wordSuggestions");
      setState(() {});
    } catch (e) {
      logger.e("Error fetching suggestions: $e");
    }
  }
}
Future<void> objectDetection(CameraImage cameraImage) async {
  final result = await vision.yoloOnFrame(
    bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
    imageHeight: cameraImage.height,
    imageWidth: cameraImage.width,
    iouThreshold: 0.25,
    confThreshold: 0.25,
    classThreshold: 0.5,
  );

  if (result.isNotEmpty) {
    setState(() {
      yoloResults = result.take(maxDetections).toList(); // Limit detections
      logger.i("Detections: $yoloResults");
      _lastDetectionTime = DateTime.now();
      _resetDetectionTimer();
     
      for (var detection in yoloResults) {
        String label = detection['tag'];
        
        // Increment stability for detected label
        detectionStability[label] = (detectionStability[label] ?? 0) + 1;
        // Check stability threshold
        if (detectionStability[label]! >= stabilityThreshold) {
          // Add stable label to recognizedLabel
       
          if (recognizedLabel.isEmpty || recognizedLabel[recognizedLabel.length - 1] != label) {
            // Add to acceptedWord if confidence is high
            if ((detection['box'][4] * 100) >= 80) {
              // acceptedWord += label;
                if (label == "SPACE"){
                     acceptedWord += recognizedLabel;
                     recognizedLabel = "";
                     acceptedWord += " ";
                }
                else{
                    recognizedLabel += label;

                    logger.i("Recognized Label: $recognizedLabel");
                }
            }
          }
 
          // Reset stability count after recognition
          detectionStability[label] = 0;
        }
      }
      // Cleanup: Only remove entries that haven't been seen in the current frame
      detectionStability.removeWhere((key, value) =>
          !yoloResults.any((result) => result['tag'] == key));
    });
    await updateSuggestions();
  }
  else if (_lastDetectionTime != null) {
    // If no new detections, check if timeout has passed
    if (DateTime.now().difference(_lastDetectionTime!).inMilliseconds >= detectionTimeout) {
      setState(() {
        yoloResults.clear();
        _lastDetectionTime = null;
      });
    }
  }
}


  Future<void> startDetection() async {
    setState(() {
      isDetecting = true;
    });
    if (controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream((image) async {
      if (isDetecting) {
        cameraImage = image;
        objectDetection(image);
      }
    });
  }

  Future<void> stopDetection() async {
    setState(() {
      isDetecting = false;
      yoloResults.clear();
      detectionStability.clear();
    });
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (yoloResults.isEmpty) return [];
    double factorX = screen.width / (cameraImage?.height ?? 1);
    double factorY = screen.height / (cameraImage?.width ?? 1);

    return yoloResults.map((result) {
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = Colors.green,
              color: Colors.white,
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    if (!isLoaded) {
      return const Loading();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(
            controller,
          ),
        ),
        if (yoloResults.isNotEmpty) ...displayBoxesAroundRecognizedObjects(size),
        Positioned(
          top: 10,
          width: MediaQuery.of(context).size.width,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: const Color.fromARGB(255, 255, 255, 255),
                ),
                child: recognizedLabel.isEmpty
                    ? const Text("Text will be displayed here")
                    : Text(recognizedLabel),
              ),
              Text(
                acceptedWord,
                style: TextStyle(fontSize: 24, color: Colors.white),
              ),
            ],
          ),
        ),
         Positioned(
          top: 100,
          width: MediaQuery.of(context).size.width,
          child: (recognizedLabel.isNotEmpty && recognizedLabel.length >= 3) ? Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Evenly space the rectangles
            children: List.generate(
            // Generate at most 3 GestureDetectors based on wordSuggestions length
            wordSuggestions.length > 3 ? 3 : wordSuggestions.length,
            (index) {
              return
               GestureDetector(
              onTap: () {
                 setState(() {
                acceptedWord += " ";
                acceptedWord += wordSuggestions[index];
                recognizedLabel = "";
                 });
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 69, 69, 69),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: recognizedLabel.isEmpty ? Text('Text') :
                 Text(wordSuggestions[index],
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            );
            },
            ),
          ):Container(),
        ),
        Positioned(
          bottom: 75,
          width: MediaQuery.of(context).size.width,
          child: Container(
            height: 80,
            width: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                width: 5,
                color: Colors.white,
                style: BorderStyle.solid,
              ),
            ),
            child: isDetecting
                ? IconButton(
                    onPressed: () async {
                      stopDetection();
                    },
                    icon: const Icon(
                      Icons.stop,
                      color: Colors.red,
                    ),
                    iconSize: 50,
                  )
                : IconButton(
                    onPressed: () async {
                      await startDetection();
                    },
                    icon: const Icon(
                      Icons.circle,
                      color: Colors.white,
                    ),
                    iconSize: 50,
                  ),
          ),
        ),
        Positioned(
          bottom: 10,
          width: MediaQuery.of(context).size.width,
 child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: () {
                    _flutterTts.speak(acceptedWord);
                  },
                  child: const Icon(Icons.speaker),
                ),
              ],
            ),
          ),
        ),
                Positioned(
          bottom: 80,
          width: MediaQuery.of(context).size.width,
 child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: () {
                     setState(() {
                      if (recognizedLabel.isNotEmpty) {
                         recognizedLabel = recognizedLabel.substring(0, recognizedLabel.length - 1); // Return the input string if it's already empty
                      }
                     if (acceptedWord.isNotEmpty && acceptedWord[acceptedWord.length - 1] != " ") {
                        acceptedWord += " ";
                     }
                     });
                  },
                  child: const Icon(Icons.backspace),
                ),
              ],
            ),
          ),
        ),
         Positioned(
          bottom: 150,
          width: MediaQuery.of(context).size.width,
 child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: () {
                     setState(() {
                    recognizedLabel = "";
                    acceptedWord = "";
                     });
                  },
                  child: const Icon(Icons.delete_forever),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
