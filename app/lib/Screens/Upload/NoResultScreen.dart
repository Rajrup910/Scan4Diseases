import 'package:flutter/material.dart';
import '../theme.dart';

class NoResultsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("No Results Found"),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min, // Occupy minimal screen space
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Themes.bluishClr.withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            Text(
              "We Couldn't Find Results",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Please try adjusting your search or check back later.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            // Add a "Try Again" Button if suitable (See below)
          ],
        ),
      ),
    );
  }
}
