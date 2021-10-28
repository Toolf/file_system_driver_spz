class Dentry {
  String name;
  int fileDescriptorId;
  bool valid;
  Dentry({
    required this.name,
    required this.fileDescriptorId,
    required this.valid,
  });
}
