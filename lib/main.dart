import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zip File Extractor',
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _filePath = '';
  String _imageName = '';
  String _targetDir = '';
  List<String> _imageNames = [];

  bool _dragging = false;

  final _imageNamesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _imageNamesController.addListener(_onImageNamesChanged);
  }

  @override
  void dispose() {
    _imageNamesController.dispose();
    super.dispose();
  }

  void _onImageNamesChanged() {
    setState(() {
      _imageName = _imageNamesController.text;
    });
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null) {
      setState(() {
        _filePath = result.files.single.path!;
      });
    }
  }

  Future<void> _pickDirectory() async {
    final directory = await getDirectoryPath();
    if (directory != null) {
      setState(() {
        _targetDir = directory;
      });
    }
  }

  Future<String?> getDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;

    final result =
        await FilePicker.platform.getDirectoryPath(initialDirectory: path);
    return result;
  }

  Future<void> _extractZip() async {
    if (_filePath.isEmpty) {
      return;
    }

    if (_targetDir.isEmpty) {
      _showErrorDialog('Please select target directory.');
      return;
    }

    final bytes = File(_filePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    if (archive.length == 1) {
      _showErrorDialog('Zip里怎么只有一个文件');
      return;
    }

    if (_imageName.isEmpty) {
      _showErrorDialog('Please enter image name.');
      return;
    }

    final imagesetDir = Directory('$_targetDir/$_imageName.imageset');
    if (!imagesetDir.existsSync()) {
      imagesetDir.createSync(recursive: true);
    }

    // Extract the contents of the Zip archive to disk.
    for (final file in archive) {
      var filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;

        if (filename.endsWith('@2x.png')) {
          filename = '$_imageName@2x.png';
        } else if (filename.endsWith('@3x.png')) {
          filename = '$_imageName@3x.png';
        } else {
          // 1x
        }
        File('${imagesetDir.path}/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }

    // mastergo.com上导出切图，默认会有123x图，但是1x图是不需要的，所以得删除1x图片
    final files = imagesetDir.listSync();
    for (final file in files) {
      if (file is File &&
          !file.path.endsWith('@2x.png') &&
          !file.path.endsWith('@3x.png')) {
        file.deleteSync();
      }
    }

    var contentsJson = '''
      {
  "images" : [
    {
      "idiom" : "iphone",
      "scale" : "1x"
    },
    {
      "filename" : "AAA123ZZZ@2x.png",
      "idiom" : "iphone",
      "scale" : "2x"
    },
    {
      "filename" : "AAA123ZZZ@3x.png",
      "idiom" : "iphone",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
    ''';
    contentsJson = contentsJson.replaceAll("AAA123ZZZ", _imageName);
    File('${imagesetDir.path}/Contents.json').writeAsStringSync(contentsJson);

    FlutterToastr.show('Zip file extracted successfully!', context,
        duration: 1, position: FlutterToastr.center);

    if (!_imageNames.contains(_imageName)) {
      setState(() {
        _imageNames.add(_imageName);
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
        DropTarget(
        onDragDone: (detail) async {
          if(detail.files.length != 1){
            return;
          }
          XFile aFile = detail.files[0];
          FileSystemEntityType type = FileSystemEntity.typeSync(aFile.path);
          if(type == FileSystemEntityType.file && aFile.name.endsWith(".zip")){
            setState(() {
              _filePath = aFile.path;
            });
            debugPrint('onDragDone: $_filePath');
          } else if(type == FileSystemEntityType.directory && aFile.name.endsWith(".xcassets")){
            // 是文件夹
            setState(() {
              _targetDir = aFile.path;
            });
          }


        },
        onDragUpdated: (details) {
          setState(() {
            // offset = details.localPosition;
          });
        },
        onDragEntered: (detail) {
          setState(() {
            _dragging = true;
           });
        },
        onDragExited: (detail) {
          setState(() {
            _dragging = false;
           });
        },
        child:
            Container(color: Colors.brown,width: double.infinity,height: double.infinity,child:  Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ElevatedButton(
                onPressed: _pickFile,
                child: const Text('选择Zip文件'),
              ),
              const SizedBox(height: 16),
              Text(_filePath),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _pickDirectory,
                child: const Text('选择输出目录'),
              ),
              const SizedBox(height: 16),
              Text(_targetDir),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imageNamesController,
                      decoration: const InputDecoration(
                        hintText: '输入图片名',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (_imageName.isNotEmpty &&
                          !_imageNames.contains(_imageName)) {
                        setState(() {
                          _imageNames.add(_imageName);
                        });
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _imageNames.length,
                  itemBuilder: (context, index) {
                    final imageName = _imageNames[index];

                    ListTile cell = ListTile(
                      title: Text(imageName),
                      onTap: () {
                        _imageNamesController.text = imageName;
                      },
                    );
                    return  Dismissible(
                          key: Key(imageName),
                          onDismissed: (direction) {
                            setState(() {
                              _imageNames.removeAt(index);
                            });
                          },
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding:const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          child: cell);

                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _extractZip,
                child: const Text('开始解压Zip'),
              ),
            ],
          ),)
        )

    );
  }
}
