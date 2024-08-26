import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Отримуємо список доступних камер
  final cameras = await availableCameras();

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(cameras: cameras),
    ),
  );
}

class TakePictureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const TakePictureScreen({super.key, required this.cameras});

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  int _currentCameraIndex = 0;
  bool _isFlashOn = false;

  @override
  void initState() {
    super.initState();
    _initializeCameraController(_currentCameraIndex);
  }

  void _initializeCameraController(int cameraIndex) {
    _controller = CameraController(
      widget.cameras[cameraIndex],
      ResolutionPreset.high,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (_isFlashOn) {
        _controller.setFlashMode(FlashMode.torch);
      } else {
        _controller.setFlashMode(FlashMode.off);
      }
    });
  }

  void _switchCamera() {
    setState(() {
      _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
      _initializeCameraController(_currentCameraIndex);
    });
  }

  void _toggleFlash() {
    setState(() {
      _isFlashOn = !_isFlashOn;
      _controller.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
    });
  }

  Future<String> _savePictureToFile(XFile image) async {
    // Читаємо зображення
    final imageBytes = await image.readAsBytes();
    final imageObject = img.decodeImage(imageBytes);

    // Коригуємо обертання зображення
    final rotatedImage = img.bakeOrientation(imageObject!);

    // Перевіряємо, чи використовується фронтальна камера
    if (widget.cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front) {
      // Віддзеркалюємо зображення для фронтальної камери
      final mirroredImage = img.flipHorizontal(rotatedImage);
      final flippedBytes = img.encodeJpg(mirroredImage);
      await File(image.path).writeAsBytes(flippedBytes);
    } else {
      // Для задньої камери просто зберігаємо відкориговане зображення
      final rotatedBytes = img.encodeJpg(rotatedImage);
      await File(image.path).writeAsBytes(rotatedBytes);
    }

    // Отримуємо шлях до тимчасової директорії
    final directory = await getTemporaryDirectory();

    // Вказуємо шлях до нового файлу
    final newPath = '${directory.path}/${DateTime.now()}.jpg';
    final newImage = await File(image.path).copy(newPath);

    // Зберігаємо файл у галерею
    await GallerySaver.saveImage(newImage.path, albumName: 'Flutter Photos');

    return newImage.path;
  }



  Future<void> _openGallery() async {
    // Вимикаємо спалах перед відкриттям галереї
    if (_isFlashOn) {
      setState(() {
        _isFlashOn = false;
        _controller.setFlashMode(FlashMode.off);
      });
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(imagePath: pickedFile.path),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller),

                Positioned(
                  top: 16,
                  right: 16,
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.switch_camera, size: 30, color: Colors.white),
                        onPressed: _switchCamera,
                      ),
                      IconButton(
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          size: 30,
                          color: Colors.white,
                        ),
                        onPressed: _toggleFlash,
                      ),
                    ],
                  ),
                ),

                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton(
                      heroTag: 'takePictureButton',
                      onPressed: () async {
                        try {
                          await _initializeControllerFuture;

                          final image = await _controller.takePicture();

                          final imagePath = await _savePictureToFile(image);

                          if (!mounted) return;

                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => DisplayPictureScreen(imagePath: imagePath),
                            ),
                          );
                        } catch (e) {
                          print(e);
                        }
                      },
                      child: const Icon(Icons.camera_alt),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 30,
                  right: 16,
                  child: FloatingActionButton(
                    heroTag: 'openGalleryButton',
                    onPressed: _openGallery,
                    child: const Icon(Icons.photo_library),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;

  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Image.file(File(imagePath)),
    );
  }
}
