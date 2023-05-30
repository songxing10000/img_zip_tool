import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
  /// zip的路径
  String _zip_file_path = '';

  /// 要取的图片名
  String _imageName = '';

  /// xcassets路径
  String _xcassetsFolderPath = '';

  /// 历史曾用名
  List<String> _imageNames = [];

  final _imageNamesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _imageNamesController.addListener(_onImageNamesChanged);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saveImageNameFilePath = prefs.getString('_imageName_key');
    final String? saveTargetDirFilePath = prefs.getString('_targetDir_key');
    final List<String>? saveImgNames = prefs.getStringList('_imageNames_key');
    setState(() {
      _imageName = saveImageNameFilePath ?? '';
      _xcassetsFolderPath = saveTargetDirFilePath ?? '';
      _imageNames = saveImgNames ?? [];
    });
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

  /// 选取zip文件
  Future<void> _pickZipFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null) {
      setState(() {
        _zip_file_path = result.files.single.path!;
      });
    }
  }

  /// 选取xcassets文件夹
  Future<void> _pickXcassetsFolder() async {
    final directory = await getDirectoryPath();
    if (directory != null) {
      setState(() {
        _xcassetsFolderPath = directory;
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('_targetDir_key', _xcassetsFolderPath);
    }
  }

  /// 获取要默认显示的文档路径
  Future<String?> getDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;

    final result =
        await FilePicker.platform.getDirectoryPath(initialDirectory: path);
    return result;
  }

  Future<void> _extractZip() async {
    if (_zip_file_path.isEmpty) {
      return;
    }

    if (_xcassetsFolderPath.isEmpty) {
      _showErrorDialog('Please select target directory.');
      return;
    }

    final bytes = File(_zip_file_path).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    if (archive.length == 1) {
      _showErrorDialog('Zip里怎么只有一个文件');
      return;
    }

    if (_imageName.isEmpty) {
      _showErrorDialog('Please enter image name.');
      return;
    }

    final imagesetDir = Directory('$_xcassetsFolderPath/$_imageName.imageset');
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
    _delete1xImg(imagesetDir);

    _writeContentJsonFile(imagesetDir);

    FlutterToastr.show('操作完成!', context,
        duration: 1, position: FlutterToastr.center);

    if (!_imageNames.contains(_imageName)) {
      setState(() {
        _imageNames.add(_imageName);
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setStringList('_imageNames_key', _imageNames);
    }
  }

  void _delete1xImg(Directory imagesetDir) {
    final files = imagesetDir.listSync();
    for (final file in files) {
      if (file is File &&
          !file.path.endsWith('@2x.png') &&
          !file.path.endsWith('@3x.png')) {
        file.deleteSync();
      }
    }
  }

  void _writeContentJsonFile(Directory imagesetDir) {
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

  /// 拖拽完毕
  void _onDragDone(DropDoneDetails detail) async {
    if (detail.files.length != 1) {
      return;
    }
    XFile aFile = detail.files[0];
    FileSystemEntityType type = FileSystemEntity.typeSync(aFile.path);
    if (type == FileSystemEntityType.file && aFile.name.endsWith(".zip")) {
      // 拖入zip文件
      setState(() {
        _zip_file_path = aFile.path;
      });
      debugPrint('onDragDone: $_zip_file_path');
    } else if (type == FileSystemEntityType.directory) {
      // 拖入文件夹
      if(aFile.name.endsWith(".xcassets")){
        // 拖入xcassets文件夹
        // 是文件夹
        setState(() {
          _xcassetsFolderPath = aFile.path;
        });
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('_targetDir_key', _xcassetsFolderPath);
      }
      // else if (??) {
      //
      // }

    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: DropTarget(
            onDragDone: (detail) {
              _onDragDone(detail);
            },
            child: buildContainer()));
  }

  Container buildContainer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: buildColumn(),
    );
  }

  Column buildColumn() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("单个切图zip文件"),
            ElevatedButton(
              onPressed: _pickZipFile,
              child: const Text('1.选择或拽入Zip文件'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(_zip_file_path),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("iOS选xcassets目录，Flutter选择有2.0x和3.0x这个目录"),
            ElevatedButton(
              onPressed: _pickXcassetsFolder,
              child: const Text('2.选择或拽入目录'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(_xcassetsFolderPath),
        const SizedBox(height: 16),
        buildRow(),
        const SizedBox(height: 16),
        Expanded(
          child: buildListView(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _extractZip,
          child: const Text('开始工作'),
        ),
      ],
    );
  }

  ListView buildListView() {
    return ListView.builder(
      itemCount: _imageNames.length,
      itemBuilder: (context, index) {
        final imageName = _imageNames[index];

        ListTile cell = ListTile(
          title: Text(imageName),
          onTap: () {
            _imageNamesController.text = imageName;
          },
        );
        return Dismissible(
            key: Key(imageName),
            onDismissed: (direction) async {
              setState(() {
                _imageNames.removeAt(index);
              });
              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              prefs.setStringList('_imageNames_key', _imageNames);
            },
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: cell);
      },
    );
  }

  Row buildRow() {
    return Row(
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
          onPressed: _clickAddToListBtn,
          child: const Text('加入列表'),
        ),
      ],
    );
  }

  void _clickAddToListBtn() async {
    if (_imageName.isNotEmpty && !_imageNames.contains(_imageName)) {
      setState(() {
        _imageNames.add(_imageName);
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setStringList('_imageNames_key', _imageNames);
    }
  }
}
