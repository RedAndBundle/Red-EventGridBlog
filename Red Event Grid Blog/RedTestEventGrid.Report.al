report 50100 "Red Test Event Grid"
{
    Caption = 'Test JQ To Event Grid';
    ApplicationArea = all;
    UsageCategory = Administration;
    ProcessingOnly = true;

    dataset
    {
        dataitem("Sales Invoice Header"; "Sales Invoice Header")
        {
            MaxIteration = 1;
            RequestFilterFields = "No.";

            trigger OnAfterGetRecord();
            begin
                if TestWithJQ then
                    CreateJQEntry("Sales Invoice Header"."No.")
                else
                    RunJQManual("Sales Invoice Header");
                Message('Tested invoice %1 %2', "Sales Invoice Header"."No.", TestWithJQ);
            end;
        }
    }

    requestpage
    {

        layout
        {
            area(content)
            {
                field(TestWithJQ; TestWithJQ)
                {
                    ApplicationArea = All;
                }
            }
        }
    }

    var
        TestWithJQ: Boolean;

    local procedure RunJQManual(RecVar: Variant)
    var
        JobQueueEntry: Record "Job Queue Entry";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(RecVar);

        JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
        JobQueueEntry."Object ID to Run" := Codeunit::"Red Create Azure Event";
        JobQueueEntry."Record ID to Process" := RecRef.RecordId;
        JobQueueEntry."Job Queue Category Code" := '';
        JobQueueEntry.Description := 'Red-SalesDocPosted';
        Codeunit.Run(Codeunit::"Red Create Azure Event", JobQueueEntry);
    end;

    local procedure CreateJQEntry(InvHeaderNo: Code[20]);
    var
        RedCreateAzureEvent: Codeunit "Red Create Azure Event";
    begin
        RedCreateAzureEvent.CreateEventGridJQEntryFromSalesDoc('', '', InvHeaderNo, '');
    end;
}