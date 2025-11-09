// Simple doGet for testing
function doGet(e) {
  // Extract 'name' parameter from URL query string
  var name = e.parameter.name || 'unknown';
  var result = searchAndListFacilities(name)

  //  var response = {
  //   message: 'Message received: ' + result
  // };

  if (result == null){
     return ContentService
    .createTextOutput(JSON.stringify("None"))
    .setMimeType(ContentService.MimeType.JSON); 
  }

  // Return JSON response
  var response = {
    name : result[0],
    adminname : result[1],
    phone : result[2],
    address : result[3]
  }

  return ContentService
    .createTextOutput(JSON.stringify(response))
    .setMimeType(ContentService.MimeType.JSON);
}

function searchAndListFacilities(name) {
  const url = "https://azcarecheck.azdhs.gov/s/sfsites/aura?r=4&aura.ApexAction.execute=1";
  const searchQuery = name; // Change this as needed

  const payload = {
    "message": JSON.stringify({
      "actions": [
        {
          "id": "84;a",
          "descriptor": "aura://ApexActionController/ACTION$execute",
          "callingDescriptor": "UNKNOWN",
          "params": {
            "namespace": "",
            "classname": "AZCCMapService",
            "method": "getAccountsMapData",
            "params": {
              "program": "Health Care",
              "programLabel": "Health Care Facilities",
              "facilityType": "",
              "facilityStatus": "Active",
              "licenseStatus": "Active",
              "searchQuery": searchQuery,
              "filterQueryParameters": "{\"isEnforcement\":false}"
            },
            "cacheable": false,
            "isContinuation": false
          }
        }
      ]
    }),
    "aura.context": JSON.stringify({
      "mode": "PROD",
      "fwuid": "VFJhRGxfRlFsN29ySGg2SXFsaUZsQTFLcUUxeUY3ZVB6dE9hR0VheDVpb2cxMy4zMzU1NDQzMi4yNTE2NTgyNA",
      "app": "siteforce:communityApp",
      "loaded": {
        "APPLICATION@markup://siteforce:communityApp": "1411_cmG25dptuXHlZVEVTc27wQ"
      },
      "dn": [],
      "globals": {},
      "uad": true
    }),
    "aura.pageURI": "/s/?licenseType=All&facilityStatus=Active&licenseStatus=Active&programType=Health%20Care%20Facilities",
    "aura.token": null
  };

  const headers = {
    "Accept": "*/*",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "Origin": "https://azcarecheck.azdhs.gov",
    "Referer": "https://azcarecheck.azdhs.gov/s/",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
  };

  const options = {
    method: "post",
    headers: headers,
    payload: payload,
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(url, options);
  const text = response.getContentText();
  const data = JSON.parse(text);

  try {
    const results = data.actions[0].returnValue.returnValue;

    // Build full detail URLs
    const baseUrl = "https://azcarecheck.azdhs.gov/s/facility-details";
    const rows = results.map(facility => {
      const facilityId = facility.facilityId;
      const facilityName = encodeURIComponent(facility.facilityLegalName);
      const url = `${baseUrl}?facilityId=${facilityId}&activeTab=details&licenseType=All&programType=Health%20Care%20Facilities&searchQuery=${facilityName}&facilityStatus=Active&licenseStatus=Active`;
      return String(url);
    });

    return fetchFacilityDetailsAndPost(rows[0]);
  } catch (err) {
    return null
  }
}


function fetchFacilityDetailsAndPost(rows) {
  const facilityUrl = rows;

  const facilityIdMatch = facilityUrl.match(/facilityId=([^&]+)/);
  if (!facilityIdMatch) throw new Error("No facilityId found in URL.");
  const facilityId = facilityIdMatch[1];

  const url = "https://azcarecheck.azdhs.gov/s/sfsites/aura?r=4&aura.ApexAction.execute=1";

  // Payload to get facility details
  const payload = {
    "message": JSON.stringify({
      "actions": [
        {
          "id": "79;a",
          "descriptor": "aura://ApexActionController/ACTION$execute",
          "callingDescriptor": "UNKNOWN",
          "params": {
            "namespace": "",
            "classname": "AZCCFacilityDetailsTabController",
            "method": "getFacilityDetails",
            "params": { "facilityId": facilityId },
            "cacheable": true,
            "isContinuation": false
          }
        }
      ]
    }),
    "aura.context": JSON.stringify({
      "mode": "PROD",
      "fwuid": "VFJhRGxfRlFsN29ySGg2SXFsaUZsQTFLcUUxeUY3ZVB6dE9hR0VheDVpb2cxMy4zMzU1NDQzMi4yNTE2NTgyNA",
      "app": "siteforce:communityApp",
      "loaded": {
        "APPLICATION@markup://siteforce:communityApp": "1411_cmG25dptuXHlZVEVTc27wQ"
      },
      "dn": [],
      "globals": {},
      "uad": true
    }),
    "aura.pageURI": `/s/facility-details?facilityId=${facilityId}`,
    "aura.token": null
  };

  const headers = {
    "Accept": "*/*",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "Origin": "https://azcarecheck.azdhs.gov",
    "Referer": facilityUrl,
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
    "Cookie": "renderCtx=%7B%22pageId%22%3A%22012744ae-1d05-46ef-b5cd-0b3067a409f7%22%7D"
  };

  const options = {
    method: "post",
    headers: headers,
    payload: payload,
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(url, options);
  const status = response.getResponseCode();
  const text = response.getContentText();
  Logger.log("HTTP Status: " + status);
  Logger.log("Response text:\n" + text);

  let json;
  try {
    json = JSON.parse(text);
  } catch (e) {
    return null;
  }

  const data = json.actions?.[0]?.returnValue?.returnValue;
  if (!data) {
    Logger.log("⚠️ No data found in response.");
    return null;
  }

  // Extract relevant fields
  const facilityName = data.legalName || "N/A";
  const adminName = data.chiefAdministrativeOfficer || "N/A";
  const phone = data.phone || "N/A";
  const address = data.address || "N/A";
  const mailingAddress = data.mailingAddress || "N/A";
  const license = data.license || "N/A";
  const expiration = data.expirationDate || "N/A";
  const capacity = data.totalCapacity || "N/A";
  const facilityType = data.facilityType || "N/A";
  const statusVal = data.facilityStatus || "N/A";

  // 🧾 Write neatly across columns
  const values = [facilityName, adminName, phone, address, mailingAddress];

return values
}
