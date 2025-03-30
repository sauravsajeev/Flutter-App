import 'dart:io';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:wakelock/wakelock.dart';
import '../../presentation/widgets/loading.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
//import 'package:path_provider/path_provider.dart';

final logger = Logger();
class YoloVideo extends StatefulWidget {
  const YoloVideo({Key? key}) : super(key: key);

  @override
  State<YoloVideo> createState() => _YoloVideoState();
}

class _YoloVideoState extends State<YoloVideo> {
  late CameraController controller;
  late List<CameraDescription> cameras;
  bool _isStreaming = false;
  String _detectedText = "";
  String EditedText = "";
  String _messages = "";
  final FlutterTts _flutterTts = FlutterTts();
  bool isLoaded = false;
  @override
  void initState() {
    super.initState();
     Wakelock.enable();
    initCamera();
    initTTS();
  }

  Future<void> initCamera() async {
    cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
     controller.initialize().then((value) {
      if (!mounted) {
        return;
      } else {
    setState(() {
      isLoaded = true;
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
    super.dispose();
  }

  Future<void> _startStreaming() async {
    setState(() {
      _isStreaming = true;
    });

    while (_isStreaming) {
      try {
        final XFile frame = await controller.takePicture();
        Uint8List imageBytes = await File(frame.path).readAsBytes();

        await _sendFrameToServer(imageBytes);
      } catch (e) {
        logger.i("Error capturing frame: $e");
      }
    }
  }

  Future<void> _sendFrameToServer(Uint8List imageBytes) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.12.159:8000/process_frame'),
    );
    request.files.add(http.MultipartFile.fromBytes('frame', imageBytes, filename: "frame.jpg"));

    var response = await request.send();
    if (response.statusCode == 200) {
    var responseData = await response.stream.bytesToString();
    setState(() {
      if (responseData != "null") {
        if  (responseData.replaceAll('"', '')  == " "){
          _detectedText = "SPACE";
        }
        else{
          _detectedText =  responseData.replaceAll('"', '') ;
        }
      }
    });
    logger.i (responseData); 
    }
    else{
      logger.e("Error On sending Frame");
    }// Returns detected letter
  }

Future<void> _resetSent() async {
 var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.12.159:8000/reset_sentence'),
    );
    var response = await request.send();
    if (response.statusCode == 200) {
    var responseData = await response.stream.bytesToString();

    _messages =  responseData; 
    }
    else{
      logger.i("Error On resetting");
      _messages =  "Error in deleting";
    }// Returns detected letter
}
Future<void> _receiveSentence() async {
      var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.12.159:8000/finish_record'),
    );
     var response = await request.send();
    if (response.statusCode == 200) {
    var responseData = await response.stream.bytesToString();
    if (responseData.isNotEmpty) {
      logger.i(responseData);
          setState(() {
            EditedText = responseData;
            _detectedText = "";
          });
        }
    }
    else{
      logger.i("Error On resetting");
    }
}
  void _stopStreaming() {
    setState(() {
      _isStreaming = false;
    });
    
  }
  void showNotification(BuildContext context, String message) {
  final snackBar = SnackBar(
    content: Text(message, style: TextStyle(fontSize: 16)),
    backgroundColor: const Color.fromARGB(255, 187, 188, 188),
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: 3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
  );

  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}
  @override
  Widget build(BuildContext context) {
    //final Size size = MediaQuery.of(context).size;
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
        //  if (responseReceived)
        Positioned( //Text display
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
                child: _detectedText.isEmpty
                    ? const Text("Text will be displayed here")
                    : Text(_detectedText),
              ),
              Text(
                EditedText,
                style: TextStyle(fontSize: 24, color: Colors.white),
              ),
            ],
          ),
        ),
        
         Positioned(// start and stop recording
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
            child: _isStreaming
                ? IconButton(
                    onPressed: () async {
                      _stopStreaming();
                      await _receiveSentence();
                      const Text("Video Recorded! Uploading...");
                    },
                    icon: const Icon(
                      Icons.stop,
                      color: Colors.red,
                    ),
                    iconSize: 50,
                  )
                : IconButton(
                    onPressed: () async {
                      await _startStreaming();
                    },
                    icon: const Icon(
                      Icons.circle,
                      color: Colors.white,
                    ),
                    iconSize: 50,
                  ),
          ),
          
        ),
        
         Positioned( //textTo speech
          bottom: 10,
          width: MediaQuery.of(context).size.width,
 child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: () {
                    _flutterTts.speak(EditedText);
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
                    _detectedText = "";
                    EditedText = "";
                    _resetSent();
                    if (_messages != "") {
                    showNotification(context, _messages) ;
                    }
                     });
                  },
                  child: const Icon(Icons.delete_forever),
                ),
              ],
            ),
          ),
        ),
          // ElevatedButton(
          //   onPressed: isRecording ? null : startRecording,
          //   child: Text(isRecording ? "Recording..." : "Start Recording"),
          // ),
          // if (recordedVideo != null) Text("Video Recorded! Uploading..."),
          // if (processedSentence.isNotEmpty)
          //   Padding(
          //     padding: const EdgeInsets.all(8.0),
          //     child: Text("Processed Sentence: $processedSentence",
          //         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          //   ),
        ],
    );
  }
}