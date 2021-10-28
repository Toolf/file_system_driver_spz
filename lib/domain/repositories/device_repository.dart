import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_system_driver/config.dart';

class Block {
  Uint8List data;

  Block(int blockSize) : data = Uint8List(blockSize);
}

// class DeviceData {
//   final List<Block> blocks;

//   DeviceData(int n) : blocks = List.generate(n, (i) => Block());

//   int write(int position, Uint8List data) {
//     int i = 0;
//     while (i < min(data.length, blocks.length * BLOCK_SIZE - position)) {
//       blocks[i].write(
//         i == 0 ? position % BLOCK_SIZE : 0,
//         data.sublist(
//           i * BLOCK_SIZE,
//           i == 0
//               ? (i + 1) * BLOCK_SIZE - position % BLOCK_SIZE
//               : (i + 1) * BLOCK_SIZE,
//         ),
//       );

//       i += BLOCK_SIZE;
//     }
//     return i;
//   }
// }

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
