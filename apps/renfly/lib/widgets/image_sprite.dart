import 'package:flutter/material.dart';

class ImageSprite extends StatelessWidget {
  const ImageSprite({super.key, required this.imagePath, required this.atLeft});

  final String imagePath;
  final bool atLeft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: atLeft ? 50 : null,
      right: atLeft ? null : 50,
      bottom: 0,
      child: Image.asset(
        imagePath,
        width: 200,
        height: 300,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback when image is not found
          return Container(
            width: 200,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_not_supported,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 8),
                Text(
                  'Image not found',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  imagePath.split('/').last,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
