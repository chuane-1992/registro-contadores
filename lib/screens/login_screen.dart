import 'package:flutter/material.dart';
import '../services/google_sheets_service.dart';
import 'home_screen.dart';
import 'manual_entry_screen.dart'; // Access to SPREADSHEET_ID

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = GoogleSheetsService();
      final isValid = await service.validateUser(
        SPREADSHEET_ID, 
        _userController.text.trim(), 
        _passController.text.trim()
      );

      if (isValid) {
        // Registrar login
        final user = _userController.text.trim();
        int? rowIndex;
        try {
           rowIndex = await service.logLogin(SPREADSHEET_ID, user);
        } catch (e) {
          print("Error logging login: $e");
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(
            username: user,
            sessionRowIndex: rowIndex,
          )),
        );
      } else {
        setState(() {
          _errorMessage = "Usuario o contraseña incorrectos";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error de conexión: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Iniciar Sesión")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_person, size: 80, color: Colors.blue),
                const SizedBox(height: 30),
                
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(10),
                    color: Colors.red.shade100,
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ),

                TextFormField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: "Usuario",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v == null || v.isEmpty ? "Requerido" : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passController,
                  decoration: const InputDecoration(
                    labelText: "Contraseña",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key),
                  ),
                  obscureText: true,
                  validator: (v) => v == null || v.isEmpty ? "Requerido" : null,
                ),
                const SizedBox(height: 30),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("ENTRAR", style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
