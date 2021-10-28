import 'dart:io';
import 'dart:typed_data';

import '../../config.dart';

class Block {
  Uint8List data;

  Block(int blockSize) : data = Uint8List(blockSize);
}

abstract class DeviceRepository {
  int get blockSize;
  int get blockCount;

  Block getBlock(int blockIndex);
  void write(int blockIndex, Block block);
  Uint8List get(int offset, int size);
}

class DeviceRepositoryImpl implements DeviceRepository {
  String path;

  /// Parameters:
  /// path - path to file where save information
  DeviceRepositoryImpl(this.path) {
    if (File(path).existsSync() == false) {
      final f = File(path).openSync(mode: FileMode.write);
      for (int i = 0; i < BLOCK_SIZE * BLOCK_COUNT; i++) {
        f.writeByteSync(0);
      }
    }
  }

  @override
  Block getBlock(int blockIndex) {
    final f = File(path).openSync(mode: FileMode.read);
    f.setPositionSync(blockIndex * blockSize);
    final b = Block(blockSize);
    b.data = f.readSync(blockSize);
    f.closeSync();
    return b;
  }

  @override
  void write(int blockIndex, Block block) {
    final f = File(path).openSync(mode: FileMode.append);
    f.setPositionSync(blockIndex * blockSize);
    f.writeFromSync(block.data);
    f.closeSync();
  }

  @override
  int get blockCount => BLOCK_COUNT;

  @override
  int get blockSize => BLOCK_SIZE;

  @override
  Uint8List get(int offset, int size) {
    /// Взагалі треба було б переписати через getBlock, але я не хочу,
    /// дай використовується даний метод рідко.
    final f = File(path).openSync(mode: FileMode.read);
    f.setPositionSync(offset);
    final data = f.readSync(size);
    f.closeSync();
    return data;
  }
}
