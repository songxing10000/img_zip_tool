import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;

class PathLabel extends StatelessWidget {
  final String text;

  const PathLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
          _openFolder(text);
      },
      child: Text(text),
    );
  }

  void _openFolder(String folderPath){
      if(folderPath.startsWith('file://')){
      launchUrl(Uri.parse(path.dirname(folderPath)));
    } else {

      launchUrl(Uri.parse('file://${path.dirname(folderPath)}'));
    }
  }
}
