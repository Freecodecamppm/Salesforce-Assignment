function doPost(e) {
  try {
    let data = {};

    // ✅ 1. Handle JSON payloads
    if (e.postData && e.postData.type === 'application/json') {
      try {
        data = JSON.parse(e.postData.contents);
      } catch (jsonErr) {
        throw new Error('Invalid JSON payload: ' + jsonErr.message);
      }
    }
    // ✅ 2. Handle form-encoded fallback
    else if (e.parameter && Object.keys(e.parameter).length > 0) {
      data = e.parameter;
    } else {
      throw new Error('No POST data received.');
    }

    // ✅ 3. Extract message safely
    const message = data.message || 'No message provided';

    // ✅ 4. Build JSON response
    const response = {
      reply: `This is your message: ${message}`
    };

    // ✅ 5. Return JSON response
    return ContentService
      .createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    // Return a structured JSON error
    const errorResponse = {
      error: true,
      message: err.message
    };
    return ContentService
      .createTextOutput(JSON.stringify(errorResponse))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
