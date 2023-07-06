import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'package:url_launcher/url_launcher.dart';

import 'PathLabel.dart';

enum FolderType {
  iOS,
  flutter,
  android,
}

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
  FolderType folderType = FolderType.iOS;

  /// zip的路径
  String _zip_file_path = '';

  /// 要取的图片名
  String _imageName = '';

  /// xcassets路径
  String _folderPath = '';

  /// 历史曾用名
  List<String> _imageNames = [];
  /// 图片信息，key图片名，value图片路径
  Map<String, String> imgInfoDict = {
    'calendar_purple_bg': '/Users/mac/Proj/MySwiftProj/NewProjTest/NewProjTest/Assets.xcassets/red_info_icon.imageset/red_info_icon@2x.png'
  };
  final _imgNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _imgNameController.addListener(_onImageNamesChanged);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saveImageNameFilePath = prefs.getString('_imageName_key');
    final String? saveTargetDirFilePath = prefs.getString('_targetDir_key');
    final List<String>? saveImgNames = prefs.getStringList('_imageNames_key');
    setState(() {
      _imageName = saveImageNameFilePath ?? '';
      _folderPath = saveTargetDirFilePath ?? '';
      _imageNames = saveImgNames ?? [];
    });
  }

  @override
  void dispose() {
    _imgNameController.dispose();
    super.dispose();
  }

  void _onImageNamesChanged() {
    setState(() {
      _imageName = _imgNameController.text;
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
  /// 复制图片名
_copyImgName() {
    String imgName = _imgNameController.text;
    if(imgName.isNotEmpty) {
       Clipboard.setData(ClipboardData(text: imgName)).then((_){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已复制： $imgName")));
      });
    }

}
  /// 选取xcassets文件夹
  Future<void> _pickFolder() async {
    final directory = await getDirectoryPath();
    if (directory == null) {
      return;
    }
    // 拖入文件夹
    if (directory.endsWith(".xcassets")) {
      folderType = FolderType.iOS;
    } else if (directory.endsWith("res")) {
      folderType = FolderType.android;
    } else if (await has2x3xImgFolderAt(directory)) {
      folderType = FolderType.flutter;
    }

    setState(() {
      _folderPath = directory;
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('_targetDir_key', _folderPath);
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

    if (_folderPath.isEmpty) {
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

    bool isIOS =
        (folderType == FolderType.iOS) && _folderPath.endsWith('.xcassets');
    final imagesetDir = isIOS
        ? Directory('$_folderPath/$_imageName.imageset')
        : Directory(_folderPath);
    bool hasSameImg = false;
    if (isIOS) {
      if (imagesetDir.existsSync()) {
        hasSameImg = true;
        FlutterToastr.show('重名了', context,
            duration: 1, position: FlutterToastr.center);
        _openFolder(imagesetDir.path);
        return;
      }

      imagesetDir.createSync(recursive: true);
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
    }
    else if (_folderPath.endsWith('res')) {
      // 安卓
      for (final file in archive) {
        var filename = file.name;
        /*
        *  mdpi/组 3.png xhdpi/组 3.png  xxhdpi/组 3.png xxxhdpi/组 3.png
        * */
        if (file.isFile && filename.endsWith('.png')) {

          if(file.name.contains('@2x')){
            // 跳过2x
            FlutterToastr.show('iOS图片zip??', context,
                duration: 1, position: FlutterToastr.center);
            return;
          }
          if(file.name.contains('@3x')){
            // 跳过3x
            FlutterToastr.show('iOS图片zip??', context,
                duration: 1, position: FlutterToastr.center);
            return;
          }
          if(!file.name.contains('dpi')){
            // 跳过flutter
            FlutterToastr.show('flutter图片zip??', context,
                duration: 1, position: FlutterToastr.center);
            return;
          }
          final data = file.content as List<int>;
          if (filename.contains('/')) {
            String folderName = filename.split('/')[0];

            String desFilePath = '${imagesetDir.path}/mipmap-$folderName/$_imageName.png';
            if(File(desFilePath).existsSync()){
              hasSameImg = true;
              FlutterToastr.show('重名了', context,
                  duration: 1, position: FlutterToastr.center);
              _openFolder(desFilePath);
              break;
            }


            File(desFilePath)
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          }
        }
      }
    }
    else {
      // flutter 1x图片放目录 2x图片放2.0x文件，3x图片放3.0x文件夹

      for (final file in archive) {
        var filename = file.name;
        /*
        *  组 3.png  2.0x/ 2.0x/组 3.png 3.0x/ 3.0x/组 3.png 4.0x/ 4.0x/组 3.png
        * */

        if (file.isFile && filename.endsWith('.png')) {
          if(file.name.contains('dpi')){
            // 跳过安卓
            FlutterToastr.show('安卓图片zip??', context,
                duration: 1, position: FlutterToastr.center);
            return;
          }
          if(file.name.contains('@2x')){
            // 跳过2x
            FlutterToastr.show('iOS图片zip??', context,
                duration: 1, position: FlutterToastr.center);
            return;
          }
          if(file.name.contains('@3x')){
            // 跳过3x
            FlutterToastr.show('iOS图片zip??', context,
                duration: 1, position: FlutterToastr.center);
            return;
          }
          final data = file.content as List<int>;
          if (filename.contains('/')) {
            String folderName = filename.split('/')[0];

            String desFilePath = '${imagesetDir.path}/$folderName/$_imageName.png';
            if(File(desFilePath).existsSync()){
              hasSameImg = true;
              FlutterToastr.show('重名了', context,
                  duration: 1, position: FlutterToastr.center);
              _openFolder(desFilePath);
              break;
            }

            File(desFilePath)
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            // 1x图片
            String desFilePath = '${imagesetDir.path}/$_imageName.png';
            if(File(desFilePath).existsSync()){
              hasSameImg = true;
              FlutterToastr.show('重名了', context,
                  duration: 1, position: FlutterToastr.center);
              _openFolder(desFilePath);
              break;
            }
            File(desFilePath)
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          }
        }
      }
    }
    if(hasSameImg){
      return;
    }
    FlutterToastr.show('操作完成!', context,
        duration: 1, position: FlutterToastr.center);

    if (_imageName.isNotEmpty && !_imageNames.contains(_imageName)) {
      setState(() {
        _imageNames.add(_imageName);
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setStringList('_imageNames_key', _imageNames);
    }

  }
  void _openFolder(String folderPath){
    if(folderPath.startsWith('file://')){
      launchUrl(Uri.parse(folderPath));
    } else {
      launchUrl(Uri.parse('file://$folderPath'));
    }
  }
  List<ArchiveFile> listFilesInDirectory(ArchiveFile directory) {
    final archive = ZipDecoder().decodeBytes(directory.content);
    return archive.where((entry) {
      return entry.isFile && entry.name.endsWith('.png');
    }).toList();
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
      if (aFile.name.endsWith(".xcassets")) {
        folderType = FolderType.iOS;
      }
      else  if (aFile.name.endsWith("res")) {
        folderType = FolderType.android;
      }
      else if (await has2x3xImgFolderAt(aFile.path)) {
        folderType = FolderType.flutter;
      }
      setState(() {
        _folderPath = aFile.path;
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('_targetDir_key', _folderPath);
    }
  }

  Future<bool> has2x3xImgFolderAt(String folderPath) async {
    final folder = Directory(folderPath);
    final files = await folder.list().toList();
    bool has2x = false;
    bool has3x = false;
    for (final file in files) {
      if (await is2xDirectory(file)) {
        has2x = true;
      } else if (await is3xDirectory(file)) {
        has3x = true;
      }
    }
    return (has2x && has3x);
  }

  Future<bool> is2xDirectory(FileSystemEntity entity) async {
    if (await isDirectory(entity)) {
      final directory = entity as Directory;
      return directory.path.endsWith('/2.0x');
    }
    return false;
  }

  Future<bool> is3xDirectory(FileSystemEntity entity) async {
    if (await isDirectory(entity)) {
      final directory = entity as Directory;
      return directory.path.endsWith('/3.0x');
    }
    return false;
  }

  Future<bool> isDirectory(FileSystemEntity entity) async {
    final type = await FileSystemEntity.type(entity.path);
    return type == FileSystemEntityType.directory;
  }
  bool isFolderExists(String folderPath){
    Directory dir = Directory(folderPath);
    if (dir.existsSync()) {
      return true;
    }
    return false;
  }

  Future<bool> isFileExists(String filePath) async {
    return await File(filePath).exists();
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
        PathLabel(text: _zip_file_path),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("iOS选xcassets目录，Flutter选有2.0x和3.0x这个目录，安卓选res目录"),
            ElevatedButton(
              onPressed: _pickFolder,
              child: const Text('2.选择或拽入目录'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PathLabel(text:_folderPath),
        const SizedBox(height: 16),
        buildRow(),
        const SizedBox(height: 16),
        Expanded(
          child: buildListView(),
        ),
        const SizedBox(height: 16),

        ElevatedButton(
          onPressed: _extractZip,
          child: const Text('4.开始工作'),
        ),
      ],
    );
  }

  ListView buildListView() {
    return ListView.builder(
      itemCount: _imageNames.length,
      itemBuilder: (context, index) {
        final imageName = _imageNames[index];
        String imgPath = imgInfoDict[imageName] ?? '';
        if(imgPath.isEmpty){
          imgPath = '/Users/mac/Proj/MySwiftProj/NewProjTest/NewProjTest/Assets.xcassets/$imageName.imageset/$imageName@2x.png';
          File file = File(imgPath);

          file.exists().then((bool exists) {
            if (!exists) {
              imgPath = '/Users/mac/Proj/MySwiftProj/NewProjTest/NewProjTest/Assets.xcassets/red_info_icon.imageset/red_info_icon@2x.png';
            }
          });
        }

        ListTile cell = ListTile(

          title: Text(imageName),
          onTap: () {
            // 点击cell
            _imgNameController.text = imageName;


          },
          leading: Image.file(File(imgPath)),
          trailing: PopupMenuButton<String>(
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'open',
                child: Text('打开'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('删除'),
              ),
            ],
            onSelected: (String value) async {
              if (value == 'open') {
                // 打开图片

                if(imgPath.isNotEmpty){
                  _openFolder(imgPath);
                }
              } else if (value == 'delete') {

                setState(() {
                  _imageNames.removeAt(index);
                });
                final SharedPreferences prefs =
                    await SharedPreferences.getInstance();
                prefs.setStringList('_imageNames_key', _imageNames);
              }
            },
          ),
        );
        return Dismissible(
            key: Key(imageName),
            onDismissed: (direction) async {
              // 左滑删除图片名
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

            textAlign: TextAlign.center,
            controller: _imgNameController,
            decoration: const InputDecoration(
              hintText: '3.输入图片名',
                contentPadding:EdgeInsets.fromLTRB(0, 0, 10, 0)
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _copyImgName,
          child: const Text('复制图片名'),
        ),
      ],
    );
  }

}
