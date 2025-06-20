import UIKit
import Social
import UniformTypeIdentifiers
import os
import MobileCoreServices

class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let item = extensionContext?.inputItems.first as? NSExtensionItem,
           let attachments = item.attachments {
            for attachment in attachments {
                print("Attachment types: \(attachment.registeredTypeIdentifiers)")
            }
        }

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = item.attachments?.first else {
            completeRequest()
            return;
        }
        
        let type = UTType.pdf.identifier
        if attachment.hasItemConformingToTypeIdentifier(type){
            print("YES", type)
            attachment.loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil) { (item, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error: \(error)")
                        self.completeRequest()
                        return
                    }
                    
                    if let fileURL = item as? URL {
                        print("Got file URL: \(fileURL)")
                        self.uploadReceiptPDF(from: fileURL)
                    } else {
                        print("Item is not a URL")
                        self.showResultAlert(success: false, message: "Failed to upload receipt")
                    }
                }
            }
        }
        else {
            showResultAlert(success: false, message: "Failed to upload receipt")
        }
    }
    
    
    func promptForAPIKey(completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "API Key Required", message: "Please enter your API Key", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "API Key"
            textField.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            if let apiKey = alert.textFields?.first?.text, !apiKey.isEmpty {
                saveTokenToKeychain(token: apiKey)
                completion(true)
            } else {
                completion(false)
            }
        })
        self.present(alert, animated: true)
    }


    
    func showResultAlert(success: Bool, message: String) {
        let alertTitle: String = if (success) {"OK"} else {"ERROR"}
        let alert = UIAlertController(title: alertTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) {_ in
            self.completeRequest()
        })
        self.present(alert, animated: true)
    }
        

    func uploadReceiptPDF(from fileURL: URL) {
        print("UPLOADING");
        guard let pdfData = try? Data(contentsOf: fileURL) else {
            completeRequest()
            return
        }
        
        guard let apiUrl = Bundle.main.object(forInfoDictionaryKey: "APIURL") as? String else {
            fatalError("API URL not found in Info.plist")
        }
        
        
        guard let url = URL(string: apiUrl) else {
            completeRequest()
            return
        }
        
        guard let apiKey = getTokenFromKeychain() else {
            // Prompt user for API Key and retry upload if successful
            promptForAPIKey { success in
                if success {
                    DispatchQueue.main.async {
                        self.uploadReceiptPDF(from: fileURL) // retry upload
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showResultAlert(success: false, message: "API Key is required to upload the receipt")
                        self.completeRequest()
                    }
                }
            }
            return
        }
        
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST";
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        
        var formData = Data()
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"receipt\"; filename=\"receipt.pdf\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        formData.append(pdfData)
        formData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        URLSession.shared.uploadTask(with: request, from: formData) {data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.showResultAlert(success: false, message: "Failed to upload receipt: \(error)")
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.showResultAlert(success: true, message: "Successfully uploaded the receipt")
                } else {
                    self.showResultAlert(success: false, message: "Failed to upload receipt: unknown error")
                }
            }
        }.resume()
        
        print("DONE")
    }
    
    
    func completeRequest() {
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    
}
