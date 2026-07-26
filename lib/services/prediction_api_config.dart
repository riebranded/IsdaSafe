import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Deployed URL of the `isdasafe-server` Render service (FastAPI + trained
/// RandomForest model + Gemini-backed feeding advisor).
const defaultPredictionApiBaseUrl = 'https://isdasafe-server.onrender.com';

/// Resolves the prediction API's base URL: [explicit] if given, else
/// `ISDASAFE_PREDICTION_API_URL` from `.env` (only if dotenv has been loaded
/// — it hasn't been in most tests), else the deployed production URL.
String resolvePredictionApiBaseUrl(String? explicit) {
  if (explicit != null) return explicit;
  if (dotenv.isInitialized) {
    final fromEnv = dotenv.env['ISDASAFE_PREDICTION_API_URL'];
    if (fromEnv != null) return fromEnv;
  }
  return defaultPredictionApiBaseUrl;
}
