codeunit 50100 "Red Create Azure Event"
{
    TableNo = "Job Queue Entry";

    trigger OnRun();
    begin
        Process(Rec);
    end;

    var
        CannotConnectErr: Label 'Cannot connect';
        WebServiceErr: Label 'Web Service error:\\Statuscode: %1\Description: %2', Comment = '%1 = HttpStatusCode %2 = ReasonPhrase';

    procedure Process(JobQueueEntry: Record "Job Queue Entry");
    var
        message: JsonArray;
    begin
        message := CreateBody(JobQueueEntry);
        SendMessage(message);
    end;

    local procedure CreateBody(JobQueueEntry: Record "Job Queue Entry") message: JsonArray
    var
        RecRef: RecordRef;
        body: JsonObject;
    begin
        RecRef.Get(JobQueueEntry."Record ID to Process");
        RecRef.SetRecFilter();
        body.Add('id', JobQueueEntry.ID);
        body.add('eventType', JobQueueEntry.Description);
        body.add('subject', StrSubstNo('%1 %2', RecRef.Name, RecRef.GetFilters()));
        body.Add('eventTime', CurrentDateTime());
        body.Add('data', GetRecData(RecRef));
        message.Add(body);
    end;

    local procedure SendMessage(message: JsonArray) Result: text
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
    begin
        Client.DefaultRequestHeaders.Add('aeg-sas-key', 'W+rdBTon0hNgMMv8pYiPlDRpqM31AlGwPKVeJ9CSgiM=');
        Content.WriteFrom(Format(message));
        Content.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');
        if not Client.Post('https://red-blog.westeurope-1.eventgrid.azure.net/api/events', Content, Response) then
            Error(CannotConnectErr);

        if not Response.IsSuccessStatusCode then
            Error(WebServiceErr, Response.HttpStatusCode, Response.ReasonPhrase);

        Response.Content.ReadAs(Result);
    end;

    local procedure GetRecData(RecRef: RecordRef) data: JsonObject
    var
        Base64: Text;
        FileType: Text;
    begin
        data.Add('table', RecRef.Name);
        data.Add('company', CompanyName);
        data.Add('bcId', GetId(RecRef));
        data.Add('bcData', GetProperties(RecRef));
        GetPdf(RecRef, Base64, FileType);
        data.Add('file', Base64);
        data.Add('filetype', FileType);
    end;

    local procedure GetId(RecRef: RecordRef) result: Guid;
    var
        FldRef: FieldRef;
    begin
        if not RecRef.FieldExist(8000) then
            exit;
        FldRef := RecRef.Field(8000);
        if FldRef.Type = FldRef.Type::Guid then
            result := FldRef.Value;
    end;

    local procedure GetProperties(RecRef: RecordRef) result: JsonObject;
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        case RecRef.Number of
            Database::"Sales Invoice Header":
                begin
                    RecRef.SetTable(SalesInvoiceHeader);
                    result.Add(ToLowerFirstChar(SalesInvoiceHeader.FieldName("No.")), SalesInvoiceHeader."No.");
                    result.Add(ToLowerFirstChar(SalesInvoiceHeader.FieldName("Bill-to Customer No.")), SalesInvoiceHeader."Bill-to Customer No.");
                    result.Add(ToLowerFirstChar(SalesInvoiceHeader.FieldName("External Document No.")), SalesInvoiceHeader."External Document No.");
                    result.Add(ToLowerFirstChar(SalesInvoiceHeader.FieldName("Your Reference")), SalesInvoiceHeader."Your Reference");
                    result.Add(ToLowerFirstChar(SalesInvoiceHeader.FieldName("Shortcut Dimension 1 Code")), SalesInvoiceHeader."Shortcut Dimension 1 Code");
                    result.Add(ToLowerFirstChar(SalesInvoiceHeader.FieldName("Shortcut Dimension 2 Code")), SalesInvoiceHeader."Shortcut Dimension 2 Code");
                end;
            else
                exit;
        end;
    end;

    local procedure GetPdf(RecRef: RecordRef; var Base64: Text; var FileType: Text);
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
        ReportSelections: Record "Report Selections";
        Base64Convert: Codeunit "Base64 Convert";
        TempBlob: Codeunit "Temp Blob";
        FileManagement: Codeunit "File Management";
        Instr: InStream;
        CustomerNo: Code[20];
    begin
        case RecRef.Number of
            Database::"Sales Invoice Header":
                begin
                    RecRef.SetTable(SalesInvoiceHeader);
                    CustomerNo := SalesInvoiceHeader."Bill-to Customer No.";
                end;
            else
                exit;
        end;

        ReportSelections.GetPdfReportForCust(TempBlob, ReportSelections.Usage::"S.Invoice", RecRef, CustomerNo);

        TempBlob.CreateInStream(Instr);
        Base64 := Base64Convert.ToBase64(Instr);
        // Base64 := 'BASE64 STRING CONTAINING THE REPORT';
        FileType := 'pdf';
    end;

    local procedure ToLowerFirstChar(Input: Text): Text
    begin
        if StrLen(Input) < 2 then
            exit(Input.ToLower());
        exit(Input.Substring(1, 1).ToLower() + Input.Substring(2));
    end;

    procedure CreateEventGridJQEntryFromSalesDoc(SalesShptHdrNo: Code[20]; RetRcpHdrNo: Code[20]; SalesInvHdrNo: Code[20]; SalesCrMemoHdrNo: Code[20]);
    begin
        case true of
            SalesInvHdrNo <> '':
                CreateSalesInvoiceJQEntries(SalesInvHdrNo);
        end;
    end;

    local procedure CreateSalesInvoiceJQEntries(SalesInvHdrNo: Code[20]);
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        if not SalesInvoiceHeader.Get(SalesInvHdrNo) then
            exit;

        CreateEventGridJQEntry(SalesInvoiceHeader, 'Red-Salesdocposted');
    end;

    procedure CreateEventGridJQEntry(RecVar: Variant; EventType: Text): Guid
    var
        JobQueueEntry: Record "Job Queue Entry";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(RecVar);

        JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
        JobQueueEntry."Object ID to Run" := Codeunit::"Red Create Azure Event";
        JobQueueEntry."Record ID to Process" := RecRef.RecordId;
        JobQueueEntry."Job Queue Category Code" := '';
        JobQueueEntry.Description := EventType;
        Codeunit.Run(Codeunit::"Job Queue - Enqueue", JobQueueEntry);
        exit(JobQueueEntry.ID);
    end;
}