import 'dart:math';
import 'dart:typed_data';

import 'package:file_system_driver/domain/repositories/device_repository.dart';
import 'package:file_system_driver/exceptions/exceptions.dart';
import 'package:file_system_driver/exceptions/invalid_path.dart';
import 'package:file_system_driver/utils/byte_formater.dart';

import 'dentry.dart';
import 'file_descriptor.dart';

abstract class FileSystem {
  int refs = 0;
  final openedFiles = <int, int>{};
  int fd = 0; // Числовий файловий дискриптор

  FileDescriptor get root;

  factory FileSystem.mount(String path) =>
      throw UnimplementedError(); // Створює екземпляр файлової системи
  void unmount();
  FileDescriptor getDescriptor(int descriptorId);
  List<Dentry> readDirectory(FileDescriptor directory);
  void create(String path);
  int open(String path);
  void close(int fd);
  Uint8List read(int fd, int offset, int size);
  void write(int fd, int offset, Uint8List data);
  void link(String name1, String name2);
  void unlink(String name);
  void truncate(String name, int size);

  int getUsedBlockAmount();
}

class FileSystemImpl implements FileSystem {
  /// Формат файлової системи для блоковго пристрою.
  /// [N][BitMap][FileDescriptros]
  /// N : 2 байти
  ///   max(32768)
  /// BitMap : 254 байт.
  ///   Максимальний розмір девайсу 260096 байт.
  ///   Кожен біт визначає чи блок занятий чи вільний.
  /// FileDescriptros : N файлових дискрипторів.
  ///   [FileDescriptor]...[FileDescriptor]
  /// FileDescriptor : 8 байт
  ///   [FileType][Refs][FileSize][blockMapAddress][2 байти зарезервовані на майбутнє]
  /// FileType : 1 байт
  ///   На даний момент можливі лише три типи, але в майбутньому вони будуть розширюватись.
  ///   0 - дискриптор не використовується
  ///   1 - файл
  ///   2 - директорія
  /// Refs : 1 байти (max = 255), цього має з запасом хватити.
  /// FileSize : 2 байти.
  ///   Максимальний розмір файлу 65536 байт.
  /// blockMapAddress : 2 байти
  ///   Номер блоку в якому зберігається інформація про зайняті блоки даного файлу.
  ///   В кінці даного файлу буде номер слідуючого блоку в якому зберігаються номера зайнятих блоків.
  ///   Кількість блоків 2032.
  ///   Тому номер блоку буде займати 2 байти, цього достатньо.
  ///   Максимальний розмір девайсу 260096 байт.

  /// Структура даних директорії : 16 байт
  ///   [valid][fileDescriptorId][name]
  /// valid: 1 байт
  ///   Показує чи даний link валідний
  ///   1 - ваділни
  ///   0 - невалідний
  /// fileDescriptorId : 2 байти
  ///   Ідентифікатор файлового дискриптору
  /// name : 13 байт
  ///   Назва файлу
  ///
  /// Так як розмір блоку 128 байт, то в одному блоці можна зберігати
  ///   9 директорних записів і 1 номер слідуючого блоку.
  /// Останні 16 байт блоку зарезервовані під адрес слідуючого блоку.
  ///   (хоча насправді використовуються і 2 байт)

  @override
  int fd;

  @override
  int refs;

  final DeviceRepository device;

  static void mkfs(String devicePath, int fdCount) async {
    final device = DeviceRepositoryImpl(devicePath);
    Uint8List data = Uint8List(256 + fdCount * 8);
    final N = int16bytes(fdCount);

    data[0] = N[0];
    data[1] = N[1];

    int mask = 1 << 7; // 10000000
    for (int i = 0; i < data.length / device.blockSize; i++) {
      data[2 + i ~/ 8] |= mask;
      mask >>= 1;
      if (mask == 0) {
        mask = 1 << 7;
      }
    }

    // root
    data[256] = 2;
    data[257] = 1;

    for (int i = 0; i < data.length; i += device.blockSize) {
      final block = Block(device.blockSize);
      for (int k = 0; k < device.blockSize && k + i < data.length; k++) {
        block.data[k] = data[k + i];
      }
      device.write(i ~/ device.blockSize, block);
    }
  }

  FileSystemImpl._(this.device)
      : fd = 0,
        refs = 0;

  @override
  FileDescriptor get root {
    return _getFileDescriptor(0);
  }

  FileDescriptor _getFileDescriptor(int fd) {
    final data = device.get(256 + 8 * fd, 8);
    final fileTypeData = data[0];
    FileType fileType;
    fileType = FileType.values[fileTypeData];

    final refs = data[1];
    final fileSize = (data[2] << 8) + data[3];
    final blockMapAddress = (data[4] << 8) + data[5];

    return FileDescriptor(
      fileSize: fileSize,
      id: fd,
      refs: refs,
      type: fileType,
      blockMapAddress: blockMapAddress,
    );
  }

  @override
  void unmount() {
    // TODO: implement unmount
    //throw UnimplementedError();
  }

  @override
  factory FileSystemImpl.mount(String path) {
    final device = DeviceRepositoryImpl(path);
    final fs = FileSystemImpl._(device);
    return fs;
  }

  @override
  void close(int fd) {
    if (!openedFiles.containsKey(fd)) {
      throw NotFoundNumericFileDescriptor();
    }
    final file = _getFileDescriptor(openedFiles[fd]!);
    openedFiles.remove(fd);
    if (file.refs == 0 && !openedFiles.values.contains(file.id)) {
      _freeFileData(file);
      file.type = FileType.unused;
    }
  }

  @override
  FileDescriptor create(String path) {
    final dirs = path.split("/");
    String pathToDir = dirs.sublist(0, dirs.length - 1).join("/");
    if (pathToDir.isEmpty) {
      pathToDir = "/";
    }
    final fileName = dirs[dirs.length - 1];
    FileDescriptor dirDescriptor = _lookUp(pathToDir);
    if (dirDescriptor.type != FileType.directory) {
      throw DirectoryNotFound();
    }

    final descriptor = _getUnusedDescriptor();
    final fileDescriptor = FileDescriptor(
      id: descriptor.id,
      type: FileType.regular,
      refs: 1,
      fileSize: 0,
      blockMapAddress: 0,
    );

    _addLinkToDirectory(dirDescriptor, fileName, fileDescriptor);
    _updateDescriptor(fileDescriptor);

    return fileDescriptor;
  }

  void _addLinkToDirectory(
    FileDescriptor dir,
    String name,
    FileDescriptor file,
  ) {
    if (name.length > 13) {
      throw Exception("Max file name size is 13");
    }
    if (name.contains("/")) {
      throw Exception("File name cannot contain '/'");
    }
    if (dir.blockMapAddress == 0) {
      final blockIndex = _getFreeBlock();
      _setBlockUsed(blockIndex);
      _clearBlock(blockIndex);
      dir.blockMapAddress = blockIndex;
      _updateDescriptor(dir);
    }

    int firstFreeDentryId = -1;
    int firstFreeDentryBlockId = -1;
    Block? firstFreeBlock;

    Block block;
    int blockId;
    List<int> blockMap;
    int address = dir.blockMapAddress;

    bool isLastBlock;
    while (true) {
      blockId = address;
      block = device.getBlock(blockId);
      blockMap = _getBlockMap(block);
      if (blockMap.length == device.blockSize ~/ 2) {
        blockMap.removeLast();
      }
      for (var blockId in blockMap) {
        final dentries = _readDentryFromBlock(blockId);
        if (firstFreeDentryId == -1) {
          for (int i = 0; i < dentries.length; i++) {
            if (!dentries[i].valid) {
              firstFreeDentryId = i;
              firstFreeDentryBlockId = blockId;
              firstFreeBlock = device.getBlock(blockId);
              break;
            }
          }
        }
        for (var d in dentries.where((d) => d.valid)) {
          if (d.name == name) {
            throw FileAlreadyExists();
          }
        }
      }
      address = _getNextBlockMapAddress(block);
      isLastBlock = address == 0;

      if (isLastBlock) {
        if (firstFreeDentryId != -1) break;
        final newBlockIndex = _getFreeBlock();
        _setBlockUsed(newBlockIndex);
        _clearBlock(newBlockIndex);
        final address = int16bytes(newBlockIndex);

        bool found = false;
        for (int i = 0; i < device.blockSize - 2; i += 2) {
          if ((block.data[i] << 8) + block.data[i + 1] == 0) {
            block.data[i] = address[0];
            block.data[i + 1] = address[1];

            firstFreeDentryId = 0;
            firstFreeDentryBlockId = newBlockIndex;
            firstFreeBlock = device.getBlock(newBlockIndex);
            device.write(blockId, block);
            found = true;
            break;
          }
        }
        if (found) break;

        final newBlockMapIndex = _getFreeBlock();
        _setBlockUsed(newBlockMapIndex);
        _clearBlock(newBlockMapIndex);
        final addressBlockMap = int16bytes(newBlockMapIndex);
        block.data[device.blockSize - 2] = addressBlockMap[0];
        block.data[device.blockSize - 1] = addressBlockMap[1];
        device.write(blockId, block);

        blockId = newBlockMapIndex;
        block = device.getBlock(blockId);
        block.data[0] = address[0];
        block.data[1] = address[1];
        device.write(newBlockMapIndex, block);

        firstFreeDentryId = 0;
        firstFreeDentryBlockId = newBlockIndex;
        firstFreeBlock = device.getBlock(newBlockIndex);
        break;
      }
    }

    firstFreeBlock!.data[firstFreeDentryId * 16] = 1;
    final fileDescriptorIdData = int16bytes(file.id);
    firstFreeBlock.data[firstFreeDentryId * 16 + 1] = fileDescriptorIdData[0];
    firstFreeBlock.data[firstFreeDentryId * 16 + 2] = fileDescriptorIdData[1];
    for (int i = 0; i < name.length; i++) {
      firstFreeBlock.data[firstFreeDentryId * 16 + 3 + i] = name.codeUnits[i];
    }
    device.write(firstFreeDentryBlockId, firstFreeBlock);

    final updatedFileRefs = FileDescriptor(
      id: file.id,
      type: file.type,
      refs: file.refs + 1,
      fileSize: file.fileSize,
      blockMapAddress: file.blockMapAddress,
    );
    _updateDescriptor(updatedFileRefs);

    final updatedDirSize = FileDescriptor(
      id: dir.id,
      type: dir.type,
      refs: dir.refs,
      fileSize: dir.fileSize + 16, // 16 - розмір дирикторного запису
      blockMapAddress: dir.blockMapAddress,
    );
    _updateDescriptor(updatedDirSize);
  }

  void _clearBlock(int blockId) {
    device.write(blockId, Block(device.blockSize));
  }

  void _setBlockUsed(int blockId) {
    if (blockId <= (126 * 8)) {
      final block = device.getBlock(0);
      final mask = (1 << 7) >> (blockId % 8);
      final byteIndex = blockId ~/ 8;
      block.data[byteIndex + 2] |= mask;
      device.write(0, block);
    } else {
      final block = device.getBlock(1);
      final mask = (1 << 7) >> (blockId % 8);
      final byteIndex = blockId ~/ 8;
      block.data[byteIndex] |= mask;
      device.write(1, block);
    }
  }

  void _setBlockUnused(int blockId) {
    if (blockId <= (126 * 8)) {
      final block = device.getBlock(0);
      final mask = (1 << 7) >> (blockId % 8);
      final byteIndex = blockId ~/ 8;
      block.data[byteIndex + 2] &= ~mask;
      device.write(0, block);
    } else {
      final block = device.getBlock(1);
      final mask = (1 << 7) >> (blockId % 8);
      final byteIndex = blockId ~/ 8;
      block.data[byteIndex] &= ~mask;
      device.write(1, block);
    }
  }

  int _getFreeBlock() {
    final block1 = device.getBlock(0);
    Uint8List data = block1.data.sublist(2);
    for (int i = 0; i < data.length; i++) {
      if (data[i] != 255) {
        int mask = (1 << 7);
        for (int k = 0; k < data.length; k++) {
          if (mask & data[i] == 0) {
            return i * 8 + k;
          }
          mask >>= 1;
          if (mask == 0) {
            mask = (1 << 7);
          }
        }
      }
    }
    final block2 = device.getBlock(1);
    data = block1.data;
    for (int i = 0; i < data.length; i++) {
      if (data[i] != 255) {
        int mask = 1 << 7;
        for (int k = 0; k < data.length; k++) {
          if (mask & data[i] == 0) {
            return i * 8 + k;
          }
          mask >>= 1;
        }
      }
    }
    throw Exception("Free block not found");
  }

  FileDescriptor _lookUp(String path) {
    FileDescriptor directory = root;
    if (path == "/") {
      return directory;
    }
    final dentries = readDirectory(directory);
    final dirs = path.split("/");
    int i = 0;
    while (i != dirs.length) {
      bool dirFound = false;
      for (var d in dentries) {
        if (d.name == dirs[i]) {
          i++;
          directory = getDescriptor(d.fileDescriptorId);
          dirFound = true;
          break;
        }
      }
      if (!dirFound) {
        throw InvalidPath();
      }
    }
    return directory;
  }

  void _updateDescriptor(FileDescriptor fd) {
    final blockId = ((fd.id * 8) ~/ device.blockSize) + 2;
    final block = device.getBlock(blockId);
    final indexInBlock = (fd.id * 8) % device.blockSize;
    //[FileType][Refs][FileSize][blockMapAddress]
    block.data[indexInBlock] = fd.type.index; // FileType
    block.data[indexInBlock + 1] = fd.refs; // Refs
    final fileSizeData = int16bytes(fd.fileSize); // FileSize
    block.data[indexInBlock + 2] = fileSizeData[0];
    block.data[indexInBlock + 3] = fileSizeData[1];
    final blockMapData = int16bytes(fd.blockMapAddress); // BlockMap
    block.data[indexInBlock + 4] = blockMapData[0];
    block.data[indexInBlock + 5] = blockMapData[1];
    device.write(blockId, block);
  }

  @override
  FileDescriptor getDescriptor(int descriptorId) {
    return _getFileDescriptor(descriptorId);
  }

  FileDescriptor _getUnusedDescriptor() {
    final nData = device.get(0, 2);
    final N = (nData[0] << 8) + nData[1];
    for (int i = 0; i < N; i += device.blockSize) {
      final index = i ~/ device.blockSize;
      final block = device.getBlock(index + 2);
      for (int k = 0; k < device.blockSize ~/ 8; k++) {
        if (k + (index * device.blockSize) ~/ 8 >= N) {
          throw Exception("Not found unused file descriptor");
        }
        final fdData = block.data.sublist(k * 8, (k + 1) * 8);
        //[FileType][Refs][FileSize][blockMapAddress]
        final fileTypeData = fdData[0];
        FileType fileType;
        fileType = FileType.values[fileTypeData];
        if (fileType != FileType.unused) {
          continue;
        }

        final refs = fdData[1];
        final fileSize = (fdData[2] << 8) + fdData[3];
        final blockMapAddress = (fdData[4] << 8) + fdData[5];

        return FileDescriptor(
          fileSize: fileSize,
          id: k + (index * device.blockSize) ~/ 8,
          refs: refs,
          type: fileType,
          blockMapAddress: blockMapAddress,
        );
      }
    }
    throw Exception("Not found unused file descriptor");
  }

  @override
  int open(String path) {
    final f = _lookUp(path);
    if (f.type != FileType.regular) {
      throw Exception("Path not to regular file");
    }
    openedFiles[++fd] = f.id;
    return fd;
  }

  @override
  Map<int, int> openedFiles = {};

  List<int> _getBlockMap(Block block) {
    final blockAddresses = <int>[];
    for (int i = 0; i < device.blockSize; i += 2) {
      int address = (block.data[i] << 8) + block.data[i + 1];
      if (address == 0) break;
      blockAddresses.add(address);
    }
    return blockAddresses;
  }

  List<Dentry> _readDentryFromBlock(int blockId) {
    final block = device.getBlock(blockId);
    final dentries = <Dentry>[];
    for (int i = 0; i < block.data.length ~/ 16; i++) {
      final valid = (block.data[i * 16]) == 1;
      final fileDescriptorId =
          (block.data[i * 16 + 1] << 8) + block.data[i * 16 + 2];
      final nameData = block.data.sublist(i * 16 + 3, (i + 1) * 16);
      String name = String.fromCharCodes(
        nameData.sublist(0, nameData.indexOf(0)),
      );
      dentries.add(Dentry(
        fileDescriptorId: fileDescriptorId,
        name: name,
        valid: valid,
      ));
    }
    return dentries;
  }

  @override
  List<Dentry> readDirectory(FileDescriptor directory) {
    if (directory.blockMapAddress == 0) {
      return [];
    }
    int address = directory.blockMapAddress;
    List<Dentry> dentries = [];

    bool isLastBlock;
    do {
      final Block block = device.getBlock(address);
      List<int> blockMap = _getBlockMap(block);
      if (blockMap.length == device.blockSize ~/ 2) {
        blockMap.removeLast();
      }
      for (var blockId in blockMap) {
        dentries.addAll(_readDentryFromBlock(blockId).where((d) => d.valid));
      }

      address = _getNextBlockMapAddress(block);
      isLastBlock = address == 0;
    } while (!isLastBlock);

    return dentries;
  }

  @override
  Uint8List read(int fd, int offset, int size) {
    if (!openedFiles.containsKey(fd)) {
      throw FileNotFound();
    }
    final file = _getFileDescriptor(openedFiles[fd]!);
    int blockAddress = file.blockMapAddress;
    final res = <int>[];

    while (true) {
      Block block = device.getBlock(blockAddress);
      List<int> blockMap = _getBlockMap(block);

      for (int bId in blockMap) {
        if (device.blockSize > offset) {
          final b = device.getBlock(bId);
          final d = b.data.sublist(
            offset,
            min(
              max(
                file.fileSize - res.length - offset,
                0,
              ),
              min(
                device.blockSize,
                size - res.length,
              ),
            ),
          );
          res.addAll(d);
          offset = 0;
          if (res.length == size || res.length == file.fileSize - offset) break;
        } else {
          offset -= device.blockSize;
        }
      }
      if (res.length == size || res.length == file.fileSize - offset) break;

      blockAddress = _getNextBlockMapAddress(block);
      bool nextBlockMapExists = blockAddress == 0;
      if (!nextBlockMapExists) break;
    }

    return Uint8List.fromList(res);
  }

  @override
  void write(int fd, int offset, Uint8List data) {
    if (!openedFiles.containsKey(fd)) {
      throw FileNotFound();
    }
    final file = _getFileDescriptor(openedFiles[fd]!);

    int blockNumber = offset ~/ device.blockSize;
    int blockIndex = file.blockMapAddress;
    Block blockMap = device.getBlock(blockIndex);

    // int fileOffset = 0;
    while (blockNumber > (device.blockSize ~/ 2 - 1) * device.blockSize) {
      blockNumber -= device.blockSize ~/ 2 - 1;
      offset -= (device.blockSize ~/ 2 - 1) * device.blockSize;
      // fileOffset += (device.blockSize ~/ 2 - 1) * device.blockSize;
      // if (fileOffset - file.fileSize >
      //     (device.blockSize ~/ 2 - 1) * device.blockSize) {
      //   // clear all
      //   for (int i = 0;
      //       i < (device.blockSize ~/ 2 - 1) * device.blockSize;
      //       i++) {
      //     final address =
      //         (blockMap.data[i * 2] << 8) + blockMap.data[i * 2 + 1];
      //     _clearBlock(address);
      //   }
      // }

      blockIndex = _getNextBlockMapAddress(blockMap);
      blockMap = device.getBlock(blockIndex);
    }

    // {
    //   final numberOfStartBlock = offset ~/ device.blockSize;
    //   final address = (blockMap.data[numberOfStartBlock * 2] << 8) +
    //       blockMap.data[numberOfStartBlock * 2 + 1];
    //   final block = device.getBlock(address);
    //   final startByteForClear = file.fileSize % device.blockSize;
    //   for (int i = startByteForClear; i < device.blockSize; i++) {
    //     block.data[i] = 0;
    //   }
    //   device.write(address, block);
    // }

    int writtenData = 0;

    while (true) {
      Block block = device.getBlock(blockIndex);
      List<int> blockMap = _getBlockMap(block);

      for (int bId in blockMap) {
        if (device.blockSize > offset) {
          final b = device.getBlock(bId);
          // if (writtenData >= file.fileSize) {
          //   b.data = Uint8List(device.blockSize); // clear
          // }
          int needToWrite =
              min(data.length - writtenData, device.blockSize - offset);
          for (int i = 0; i < needToWrite; i++) {
            b.data[i + offset] = data[i];
          }
          device.write(bId, b);

          offset = 0;
          writtenData += needToWrite;
          if (writtenData == data.length) break;
        } else {
          offset -= device.blockSize;
        }
      }
      if (writtenData == data.length) break;

      blockIndex = _getNextBlockMapAddress(block);
      bool nextBlockMapExists = blockIndex == 0;
      if (!nextBlockMapExists) break;
    }
    if (writtenData != data.length) {
      throw Exception("Not enough file memory to write all data");
    }
  }

  @override
  void link(String name1, String name2) {
    final d = _lookUp("/");
    final file = _lookUp(name1);
    _addLinkToDirectory(d, name2, file);
  }

  @override
  void unlink(String name) {
    final d = _lookUp("/");
    final dentries = readDirectory(d);
    for (int i = 0; i < dentries.length; i++) {
      if (dentries[i].name == name) {
        int blockMapNumber =
            i ~/ (device.blockSize ~/ 16 * (device.blockSize ~/ 2 - 1));
        Block blockMap = device.getBlock(d.blockMapAddress);
        while (blockMapNumber != 0) {
          final address = _getNextBlockMapAddress(blockMap);
          blockMap = device.getBlock(address);
          blockMapNumber--;
        }

        int blockNumber =
            (i % (device.blockSize ~/ 2 - 1)) ~/ (device.blockSize ~/ 16);
        final blockAddress = (blockMap.data[blockNumber * 2] << 8) +
            blockMap.data[blockNumber * 2 + 1];
        Block block = device.getBlock(blockAddress);
        for (int k = 0; k < device.blockSize ~/ 16; k++) {
          final nameData = block.data.sublist(k * 16 + 3, (k + 1) * 16);
          String name =
              String.fromCharCodes(nameData.sublist(0, nameData.indexOf(0)));
          if (name == dentries[i].name) {
            block.data[k * 16] = 0; // set invalid
            device.write(blockAddress, block);

            final fileDescriptorId =
                (block.data[k * 16 + 1] << 8) + block.data[k * 16 + 2];
            final file = _getFileDescriptor(fileDescriptorId);
            file.refs--;
            if (file.refs == 0 && !openedFiles.values.contains(file.id)) {
              _freeFileData(file);
              file.type = FileType.unused;
            }
            _updateDescriptor(file);
            break;
          }
        }
        break;
      }
    }
  }

  void _freeFileData(FileDescriptor file) {
    print("Free file ${file.id}");
    int blockMapAddress = file.blockMapAddress;
    while (blockMapAddress != 0) {
      Block blockMap = device.getBlock(blockMapAddress);
      bool isFree = false;
      for (int blockIndex = 0;
          blockIndex < device.blockSize ~/ 2 - 1;
          blockIndex++) {
        final address = (blockMap.data[blockIndex * 2] << 8) +
            blockMap.data[blockIndex * 2 + 1];
        if (address == 0) {
          return;
        }
        _setBlockUnused(address);
      }
      blockMapAddress = _getNextBlockMapAddress(blockMap);
    }
  }

  int _getNextBlockMapAddress(Block blockMap) {
    return (blockMap.data[device.blockSize - 2] << 8) +
        blockMap.data[device.blockSize - 1];
  }

  @override
  void truncate(String name, int size) {
    /// Якщо truncate збільшує розмір файлу, то використати оптимізацію
    /// і не створювати блоки, вміст яких складається з нулів.
    /// >> Тоді прийдеться при зменшенні розміру файлу затирати дані які були нулями.
    FileDescriptor file = _lookUp(name);
    if (size < file.fileSize) {
      int needToFreeBocks = (file.fileSize - size) ~/ device.blockSize;

      final blockMaps = <Block>[];
      final blockMapAddresses = <int>[];
      int blockMapAddress = file.blockMapAddress;
      while (blockMapAddress != 0) {
        Block blockMap = device.getBlock(blockMapAddress);

        blockMaps.add(blockMap);
        blockMapAddresses.add(blockMapAddress);

        blockMapAddress = _getNextBlockMapAddress(blockMap);
      }
      int blockCount = (file.fileSize / device.blockSize).ceil();
      while (needToFreeBocks != 0) {
        int i = blockCount % (device.blockSize ~/ 2 - 1) - 1;
        for (; i >= 0 && needToFreeBocks > 0; i--) {
          final address = (blockMaps.last.data[i * 2] << 8) +
              blockMaps.last.data[i * 2 + 1];
          _clearBlock(address);
          _setBlockUnused(address);
          needToFreeBocks--;
        }
        if (i == -1) {
          blockMaps.removeLast();
          _clearBlock(blockMapAddresses.last);
          _setBlockUnused(blockMapAddresses.removeLast());
        }

        if (blockMaps.isNotEmpty) {
          final blockMap = blockMaps.last;
          final blockMapAddress = blockMapAddresses.last;
          blockMap.data[device.blockSize - 2] = 0;
          blockMap.data[device.blockSize - 1] = 0;
          device.write(blockMapAddress, blockMap);
        }
      }

      file.fileSize = size;
      _updateDescriptor(file);
    } else {
      int blockUsed = (file.fileSize / device.blockSize).ceil();
      int needToTakeBlocks = (size / device.blockSize).ceil() - blockUsed;

      int lastBlockMapAddress;
      Block lastBlockMap;
      int nextBlockMapAddress = file.blockMapAddress;
      if (nextBlockMapAddress == 0) {
        nextBlockMapAddress = _getFreeBlock();
        _setBlockUsed(nextBlockMapAddress);
        file.blockMapAddress = nextBlockMapAddress;
        _updateDescriptor(file);
      }
      do {
        lastBlockMapAddress = nextBlockMapAddress;
        lastBlockMap = device.getBlock(lastBlockMapAddress);
        nextBlockMapAddress = _getNextBlockMapAddress(lastBlockMap);
      } while (nextBlockMapAddress != 0);

      while (needToTakeBlocks != 0) {
        final freeBlockAddress = _getFreeBlock();
        _setBlockUsed(freeBlockAddress);
        final address = int16bytes(freeBlockAddress);
        lastBlockMap.data[blockUsed % (device.blockSize ~/ 2 - 1) * 2] =
            address[0];
        lastBlockMap.data[blockUsed % (device.blockSize ~/ 2 - 1) * 2 + 1] =
            address[1];
        needToTakeBlocks--;
        blockUsed++;
        if (blockUsed % (device.blockSize ~/ 2 - 1) == 0) {
          final nextBlockMapIndex = _getFreeBlock();
          _setBlockUsed(nextBlockMapIndex);
          final nextBockMapAddress = int16bytes(nextBlockMapIndex);
          lastBlockMap.data[device.blockSize - 2] = nextBockMapAddress[0];
          lastBlockMap.data[device.blockSize - 1] = nextBockMapAddress[1];

          device.write(lastBlockMapAddress, lastBlockMap);

          lastBlockMapAddress = _getNextBlockMapAddress(lastBlockMap);
          lastBlockMap = device.getBlock(lastBlockMapAddress);
        }
      }
      if (blockUsed % (device.blockSize ~/ 2 - 1) != 0) {
        device.write(lastBlockMapAddress, lastBlockMap);
      }
      file.fileSize = size;
      _updateDescriptor(file);
    }
  }

  int getUsedBlockAmount() {
    int count = 0;
    Block block;

    block = device.getBlock(0);
    for (int byteIndex = 2; byteIndex < device.blockSize; byteIndex++) {
      for (int mask = (1 << 7); mask != 0; mask >>= 1) {
        bool isUsed = (block.data[byteIndex] & mask) != 0;
        count += isUsed ? 1 : 0;
      }
    }
    block = device.getBlock(1);
    for (int byteIndex = 0; byteIndex < device.blockSize; byteIndex++) {
      for (int mask = (1 << 7); mask != 0; mask >>= 1) {
        bool isUsed = (block.data[byteIndex] & mask) != 0;
        count += isUsed ? 1 : 0;
      }
    }
    return count;
  }
}
