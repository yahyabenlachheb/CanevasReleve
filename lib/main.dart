import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSV Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const CsvReaderScreen(),
    );
  }
}

class CsvReaderScreen extends StatefulWidget {
  const CsvReaderScreen({super.key});

  @override
  _CsvReaderScreenState createState() => _CsvReaderScreenState();
}

class _CsvReaderScreenState extends State<CsvReaderScreen> {
  List<List<dynamic>> csvData = [];
  int currentIndex = 0;
  final List<TextEditingController> controllers = [];
  bool fileLoaded = false;
  String? fileName;
  File? csvFile;
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadLastOpenedFile();
  }

  String _formatDate(String dateString) {
    try {
      if (dateString.contains('-')) {
        final date = DateTime.parse(dateString);
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      } else if (dateString.contains('/')) {
        final parts = dateString.split('/');
        if (parts.length == 3) {
          // Handle both DD/MM/YYYY and MM/DD/YYYY formats
          if (int.tryParse(parts[0])! > 12) { // If first part > 12, it's likely day
            return '${parts[0].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[2]}';
          }
          return '${parts[1].padLeft(2, '0')}/${parts[0].padLeft(2, '0')}/${parts[2]}';
        }
        return dateString;
      }
      return dateString;
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _loadLastOpenedFile() async {
    final SharedPreferences prefs = await _prefs;
    final String? lastFilePath = prefs.getString('last_csv_path');

    if (lastFilePath != null && await File(lastFilePath).exists()) {
      csvFile = File(lastFilePath);
      fileName = csvFile!.path.split('/').last;
      await _loadCsvFromFile();
    }
  }

  Future<void> _saveLastOpenedFile(String path) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString('last_csv_path', path);
  }

  void _initializeControllers() {
    for (var controller in controllers) {
      controller.dispose();
    }
    controllers.clear();

    if (csvData.isNotEmpty && csvData.length > 1) {
      for (int i = 0; i < csvData[0].length; i++) {
        controllers.add(TextEditingController());
      }
      _updateControllers();
    }
  }

  Future<void> _pickCsvFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        csvFile = File(result.files.single.path!);
        fileName = result.files.single.name;
        await _saveLastOpenedFile(csvFile!.path);
        await _loadCsvFromFile();
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _loadCsvFromFile() async {
    if (csvFile == null) return;

    try {
      final fileContent = await csvFile!.readAsString();
      csvData = const CsvToListConverter(
        shouldParseNumbers: false,
        allowInvalid: true,
      ).convert(fileContent);

      if (csvData.isEmpty || csvData.length < 2) {
        throw Exception('CSV file is empty or has no data rows');
      }

      setState(() {
        fileLoaded = true;
        currentIndex = 0;
        _initializeControllers();
      });
    } catch (e) {
      _showError('Error loading CSV file: $e');
      setState(() {
        fileLoaded = false;
        csvData = [];
      });
    }
  }

  void _updateControllers() {
    if (currentIndex + 1 >= csvData.length) return;

    for (int i = 0; i < controllers.length; i++) {
      if (csvData[0][i].toString().toLowerCase().contains('date')) {
        controllers[i].text = _formatDate(csvData[currentIndex + 1][i].toString());
      } else {
        controllers[i].text = csvData[currentIndex + 1][i].toString();
      }
    }
  }

  void _nextLine() {
    if (currentIndex + 2 < csvData.length) {
      setState(() {
        currentIndex++;
        _updateControllers();
      });
    } else {
      _showMessage('Reached end of file');
    }
  }

  void _prevLine() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
        _updateControllers();
      });
    } else {
      _showMessage('Already at first record');
    }
  }

  Future<void> _saveChanges() async {
    if (csvFile == null) {
      _showError('No file is currently open');
      return;
    }

    try {
      for (int i = 0; i < controllers.length; i++) {
        csvData[currentIndex + 1][i] = controllers[i].text;
      }

      String updatedCsv = const ListToCsvConverter().convert(csvData);
      await csvFile!.writeAsString(updatedCsv);

      _showMessage('Changes saved to ${csvFile!.path}');
    } catch (e) {
      _showError('Error saving changes: $e');
    }
  }

  Future<void> _exportCsv() async {
    if (csvFile == null) {
      _showError('No file is currently open');
      return;
    }

    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV File',
        fileName: 'modified_$fileName',
        allowedExtensions: ['csv'],
      );

      if (outputFile != null) {
        String updatedCsv = const ListToCsvConverter().convert(csvData);
        await File(outputFile).writeAsString(updatedCsv);
        _showMessage('File saved to $outputFile');
      }
    } catch (e) {
      _showError('Error exporting file: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CSV Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _pickCsvFile,
            tooltip: 'Open CSV file',
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _exportCsv,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (fileName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Current file: $fileName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            
            if (!fileLoaded)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('No CSV file loaded'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _pickCsvFile,
                      child: const Text('Open CSV File'),
                    ),
                  ],
                ),
              )
            else if (csvData.isEmpty || csvData.length <= 1)
              const Center(child: Text('No data available in the CSV file'))
            else
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Record ${currentIndex + 1} of ${csvData.length - 1}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Expanded(
                      child: ListView.builder(
                        itemCount: csvData[0].length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  csvData[0][index],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: controllers[index],
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: _prevLine,
                          child: const Text('Previous'),
                        ),
                        ElevatedButton(
                          onPressed: _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'Save Changes',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _nextLine,
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}