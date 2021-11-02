import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:file_system_driver/domain/entities/file_descriptor.dart';
import 'package:file_system_driver/domain/entities/file_system.dart';

void main(List<String> arguments) async {
  String filePath = "information_device.txt";
  FileSystem? fs;
  String cwd = "/";

  String _simplifyPath(String path) {
    return path.replaceAll("../", "").replaceAll("./", "");
  }

  String _getAbsolutePath(String path) {
    return path[0] == "/" ? path : _simplifyPath(cwd + path);
  }

  void mkfs(int n) async {
    FileSystemImpl.mkfs(filePath, n);
  }

  void mount() {
    if (fs != null) {
      throw Exception("Fs was mounted");
    }
    fs = FileSystemImpl.mount(filePath);
  }

  void unmount() {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }
    fs!.unmount();
    fs = null;
  }

  void fstat(int decsriptorId) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }
    FileDescriptor descriptor = fs!.getDescriptor(decsriptorId);
    print("Descriptro #$decsriptorId\n"
        "File type: ${descriptor.type.name}\n"
        "Reference count: ${descriptor.refs}\n"
        "File size: ${descriptor.fileSize}\n");
  }

  void ls() {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }
    final dentries = fs!.readDirectory(fs!.lookUp(cwd));
    print("Dir:");
    for (var d in dentries) {
      print(
        "File name: ${d.name}\t|\t"
        "Valid: ${d.valid}\t|\t"
        "${d.valid ? 'ID: ${d.fileDescriptorId}' : ''}",
      );
    }
  }

  void create(String name) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }
    fs!.createFile(_getAbsolutePath(name));
  }

  int open(String name) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }
    final fd = fs!.open(_getAbsolutePath(name));
    print("Fd: $fd");
    return fd;
  }

  void close(int fd) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.close(fd);
  }

  void read(int fd, int offset, int size) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    final r = fs!.read(fd, offset, size);
    print("Data: $r");
  }

  void write(int fd, int offset, Uint8List data) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.write(fd, offset, data);
  }

  void link(String name1, String name2) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.link(_getAbsolutePath(name1), _getAbsolutePath(name2));
  }

  void unlink(String name) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.unlink(_getAbsolutePath(name));
  }

  void truncate(String name, int size) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    print(_getAbsolutePath(name));
    fs!.truncate(_getAbsolutePath(name), size);
  }

  void getUsedBlockAmount() {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    print("Used blocks: ${fs!.getUsedBlockAmount()}");
  }

  void mkdir(String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.createDirectory(_getAbsolutePath(path));
  }

  void rmdir(String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.removeDirectory(_getAbsolutePath(path));
  }

  void pwd() {
    print(cwd);
  }

  void cd(String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    String newCwd = _getAbsolutePath(path);

    if (fs!.isDirExists(newCwd)) {
      if (path == "..") {
        cwd = cwd.substring(
            0, cwd.substring(0, cwd.length - 1).lastIndexOf("/") + 1);
        if (cwd.isEmpty) {
          cwd = "/";
        }
      } else if (path == ".") {
        return;
      } else if (newCwd == "/") {
        cwd = "/";
      } else {
        cwd = newCwd + "/";
      }
    } else {
      print("Directory not found");
    }
  }

  void symlink(String str, String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.createSymlink(_getAbsolutePath(path), str);
  }

  var parser = ArgParser()
    ..addOption(
      "n",
    )
    ..addOption(
      "id",
    )
    ..addOption(
      "fd",
    )
    ..addOption(
      "path",
    )
    ..addOption(
      "offset",
    )
    ..addOption(
      "size",
    )
    ..addOption(
      "data",
    )
    ..addOption(
      "name",
    )
    ..addOption(
      "name1",
    )
    ..addOption(
      "name2",
    )
    ..addOption(
      "str",
    )
    ..addCommand(
      'mkfs',
    )
    ..addCommand(
      'create',
    )
    ..addCommand(
      "mount",
    )
    ..addCommand(
      "unmount",
    )
    ..addCommand(
      "ls",
    )
    ..addCommand(
      'exit',
    )
    ..addCommand(
      'fstat',
    )
    ..addCommand(
      'open',
    )
    ..addCommand(
      'close',
    )
    ..addCommand(
      'read',
    )
    ..addCommand(
      'write',
    )
    ..addCommand(
      'link',
    )
    ..addCommand(
      'unlink',
    )
    ..addCommand(
      'truncate',
    )
    ..addCommand(
      'usedBlocks',
    )
    ..addCommand(
      'mkdir',
    )
    ..addCommand(
      'rmdir',
    )
    ..addCommand(
      'cd',
    )
    ..addCommand(
      'pwd',
    )
    ..addCommand(
      'symlink',
    );

  while (true) {
    try {
      stdout.write("$cwd >> ");
      var args = stdin
          .readLineSync(
            encoding: Encoding.getByName('utf-8')!,
          )!
          .split(" ");

      var results = parser.parse(args);
      if (results.command == null) continue;
      final command = results.command as ArgResults;
      switch (results.command!.name) {
        case "pwd":
          pwd();
          break;
        case "mkfs":
          mkfs(int.parse(results["n"]));
          break;
        case "create":
          create(results["name"]);
          break;
        case "mount":
          mount();
          break;
        case "unmount":
          unmount();
          break;
        case "ls":
          ls();
          break;
        case "fstat":
          fstat(int.parse(results["id"]));
          break;
        case "close":
          close(int.parse(results["fd"]));
          break;
        case "open":
          open(results["path"]);
          break;
        case "read":
          int fd = int.parse(results["fd"]);
          int offset = int.parse(results["offset"]);
          int size = int.parse(results["size"]);
          read(fd, offset, size);
          break;
        case "write":
          int fd = int.parse(results["fd"]);
          int offset = int.parse(results["offset"]);
          Uint8List data =
              Uint8List.fromList(results["data"].toString().codeUnits);
          write(fd, offset, data);
          break;
        case "link":
          String name1 = results["name1"];
          String name2 = results["name2"];
          link(name1, name2);
          break;
        case "unlink":
          String name = results["name"];
          unlink(name);
          break;
        case "truncate":
          String name = results["name"];
          int size = int.parse(results["size"]);
          truncate(name, size);
          break;
        case "usedBlocks":
          getUsedBlockAmount();
          break;
        case "mkdir":
          mkdir(results["path"]);
          break;
        case "cd":
          cd(results["path"]);
          break;
        case "rmdir":
          rmdir(results["path"]);
          break;
        case "symlink":
          symlink(results["str"], results["path"]);
          break;
        case "exit":
          exit(0);
        default:
      }
    } on Exception catch (e) {
      print(e.toString());
    }
  }
}
