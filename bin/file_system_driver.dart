import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:file_system_driver/domain/entities/dentry.dart';
import 'package:file_system_driver/domain/entities/file_descriptor.dart';
import 'package:file_system_driver/domain/entities/file_system.dart';

void main(List<String> arguments) async {
  String filePath = "information_device.txt";
  FileSystem? fs;
  int cwdDescriptorId = 0;

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
    final dentries = fs!.readDirectory(fs!.getDescriptor(cwdDescriptorId));
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
    fs!.createFile(name, cwdDescriptorId);
  }

  int open(String name) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }
    final fd = fs!.open(name, cwdDescriptorId);
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

    fs!.link(name1, name2, cwdDescriptorId);
  }

  void unlink(String name) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.unlink(name, cwdDescriptorId);
  }

  void truncate(String name, int size) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.truncate(name, size, cwdDescriptorId);
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

    fs!.createDirectory(path, cwdDescriptorId);
  }

  void rmdir(String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.removeDirectory(path, cwdDescriptorId);
  }

  String pwd() {
    if (cwdDescriptorId == 0) {
      return '/';
    }
    FileDescriptor descriptor;
    String path = "";
    String cwd = "";
    List<Dentry> dentries;
    int descriptorId = cwdDescriptorId;
    do {
      path = path + "../";
      descriptor = fs!.lookUp(path, descriptorId);
      dentries = fs!.readDirectory(descriptor);
      final name =
          dentries.firstWhere((d) => d.fileDescriptorId == descriptorId).name;
      cwd = "/" + name + cwd;
    } while (dentries.firstWhere((d) => d.name == ".").fileDescriptorId ==
        descriptorId);

    print(cwd);
    return cwd;
  }

  void cd(String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    cwdDescriptorId = fs!.lookUp(path, cwdDescriptorId).id;
  }

  void symlink(String str, String path) {
    if (fs == null) {
      throw Exception("Fs wasn't mounted");
    }

    fs!.createSymlink(path, str, cwdDescriptorId);
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
      if (fs != null) {
        stdout.write("${pwd()} >> ");
      } else {
        stdout.write("> ");
      }
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
          cd(results["path"].toString());
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
