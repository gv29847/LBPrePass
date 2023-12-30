'** LB PrePass.

'**********************
'* MAIN DATA DEFINITIONS
'**********************

[WindowSetup]
NOMAINWIN 'Mainwin used for debug only
    '*WindowWidth = 931 : WindowHeight = 275
    '*UpperLeftX = INT((DisplayWidth-WindowWidth)/2)
    '*UpperLeftY = INT((DisplayHeight-WindowHeight)/2)

[ControlSetup]
'statictext  #main.static1, "Enter the full path for the (existing) source file", 20, 20, 355, 25
'statictext  #main.static2, "Enter the base path for the  output files", 20, 50, 355, 25
'statictext  #main.static3, "Then click OK", 37, 80, 260, 20
'stylebits   #main, _BS_MULTILINE, 0, 0, 0
'button      #main.OK, "OK", [MainEntry], UL, 195, 100, 180, 70
'*            TextboxColor$ = "White"
'button      #main.Quit, "EXIT", [quit], UL, 395, 100, 180, 70
'*            TextboxColor$ = "White"
'textbox     #main.SourceFilePath, 370, 15, 480, 30
'textbox     #main.OutputFilesBasePath, 370, 50, 480, 30

'* General Globals
global      True, False, RawIL$,  LineNum, SourcePath$
global      InputLine$, LCaseInputLine$, Token$
global      TypeOfDec$  '*  Alternatives are: "is an Array", "is a Local", "is a Global", "is a Function", "is a Subroutine",_
'*                                       "is a local to Function",  "is a local to Subroutine","is a parameter of Function", "is a parameter of Subroutine"
global      FunSubName$ '* Name of a function or sub. Applies to Declaration in first pass, variable scope in the second. Defaults to "Global"
global      CurrentFunSub$  '* "Subroutine|Function","<name of the function or subroutine> that the current code line is in.
global      VarLoc$         '* Alternatives are "is Outside all FunSub",  "is in Subroutine", or "is in Function"
global      CurrentVarArrayPtr    '* Records the VarArray location at which the current token was found.
global      SavedLine$, MoreLine, Var$
global      OverlappingDeclarations     '* True if a Global declaration and a 'Loc declaration outside of funsubs either have the same name
'*                                                             as one another or either have the same name as a funsub local

'* Data for array Functions
'* Note that the arrays start empty, with the start pointer at zero and the end pointer at 1. The 0'th entry is not used, it is always empty.
'* When the first entry is made is goes in location 1, the end pointer goes to 2, the start remains at 0. When the array is emptied
'* - which is from the start - the start pointer follows, pointing to 1 when the first entry is removed.
global BigArraySize, SmallArraySize
BigArraySize = 2000
SmallArraySize = 200
dim         ArrayArray$(BigArraySize)
global       ArrayArrayEndPointer  '* largest (first available) array position without a valid entry
dim         DecArray$(BigArraySize)
global       DecStartPointer  '* (DecStartPointer + 1) is the smallest array position with a valid entry, range is 0 to BigArraySize - 1
global       DecEndPointer  '* largest (first available) array position without a valid entry, range is 1 to BigArraySize
global       DecFoundAt     '* DecArray$ entry at which a match for Token, TypeOfDec$ & FunSubName has been found
dim         VarArray$(BigArraySize)
global       VarStartPointer  '* (VarStartPointer + 1) is the smallest array position with a valid entry, range is 0 to BigArraySize - 1
global       VarEndPointer   '* largest (first available) array position without a valid entry, range is 1 to BigArraySize
dim info$(10, 10) '* For "OpenFile"

'* Initialisations

ArrayArrayEndPointer = 1 : DecStartPointer = 0 : VarStartPointer = 0 : DecEndPointer = 1 : VarEndPointer = 1
True = 1 : False = 0 : SavedLine$ = "" : MoreLine = False : CurrentFunSub$ = "" : VarLoc$ = "is Outside all FunSub"
OverlappingDeclarations = False

'******************
'* MAIN PROGRAM BODY
'******************

[MainEntry]
IF OpenFiles() = True THEN
    LineNum = 0
    WHILE GetLine() = True
    '* Call PrintArrays
        WHILE  ThereIsArrayDec() = True '* Each loop removes (L to R) an array declaration from "InputLine$" & stores it in "Token$",
                                        '*  and TypeOfDec$ is set to "Array"
            Call AddArrayDec    '* Token is added to the ArrayArray$ unless it is already there - duplication is ignored
        WEND '* If this line was an array declaration line, InputLine$ is left empty, otherwise it is unchanged
        WHILE  ThereIsDec() = True '* Each loop removes (L to R) a declaration from "InputLine$", saves it as Token$, & saves TypeOfDec$. If a funsub is found its data is saved.
            If TokenInDecList() = False THEN
                Call TokenFiFo "Dec"
            Else
                CALL AddMdFlagToTokenInDecList
            End If
        WEND
    WEND

END IF
'* Call PrintArrays
'* Print "**"
close #Source

open SourcePath$ for input as #Source
LineNum = 0 : MoreLine = False : TypeOfDec$ = "" : Token$ = "" : VarLoc$ = "is Outside all FunSub"
CurrentFunSub$ = ""
MoreLine = False
WHILE GetLine() = True
    Call SetVarType         '* This determines the current scope, & eliminates funsub declaration and end lines as they cannot contain a var.
    If InputLine$ <> "" then
        Call VarPrePass      '* This simplifies the whole InputLine$ and preconditions it for a var search
        WHILE  ThereIsVar() = True  '* Each loop removes (L to R) a var from "InputLine$" & saves it as Token$.
            If TokenInVarList() = False Then '* add it to the var FiFo
                Call TokenFiFo "Var"
            Else
                CALL IncrementUseCountForTokenInVarList '* deal with repeat variable use
            End If
            CALL AddDeclarationStatus '* to record whether the variable is declared
        WEND
    End If
'*    Call PrintArrays
WEND '* for  GetLine

    CALL SaveGoodDecToFile
    CALL SaveBadDecToFile
    CALL SaveVariablesToFile
    CALL SaveUndeclaredVariablesToFile
    close #Source
    close #Declarations
    close #MultiDeclarations
    close #Variables
    close #UnDecVar
    'close #main
Notice "Normal Exit!" + chr$(13) + "Your results are ready" + chr$(13) + "Click OK to Exit"
[quit]
END '* of Main Program Body

'******************************************************
'* FUNCTION / SUBROUTINE DEFINITIONS
'******************************************************

'***************************************************************************************
'* FUNCTIONS / SUBROUTINES WHICH ONLY DO INPUT FILE HANDLING
'***************************************************************************************

Function OpenFiles()
'Loc BasePath$, string$, x

'* Open a configuration -  ini - file if it is available, else create one
files DefaultDir$, "LBPrePas.ini", info$()
x = val(info$(0,0))
If x = 0 then ' the config file is not present
    Open DefaultDir$ + "\LBPrePas.ini" for output as #ini
    print #ini, DefaultDir$ '* dummy for the source file folder
    print #ini, DefaultDir$ '* dummy for the output file folder
    Close #ini
end if '* ini file has been created with default / dummy paths inserted

Open DefaultDir$ + "\LBPrePas.ini" for input as #ini '* may contain dummy paths, or sticky paths from the previous run
line input #ini, SourcePath$
close #ini
SourcePath$ = SourcePath$ + "\*.*"
string$ = "IDENTIFY THE SOURCE FILE YOU WISH EXAMINED"

filedialog string$, SourcePath$, SourcePath$
if SourcePath$ = "" then
    notice "No file chosen!"
    goto [ExitOpenFiles]
end if

'* Create a folder to hold the output if it is not already available
x = mkdir("LBPrePasOutput") 
'* the output file exists

'* The ini file must exist from the previous code, so get the default base path
Open DefaultDir$ + "\LBPrePas.ini" for input as #ini
line input #ini, BasePath$
line input #ini, BasePath$ '* second line holds the base path - but this is not yet used
close #ini


BasePath$ = DefaultDir$ + "\LBPrePasOutput"

Open DefaultDir$ + "\LBPrePas.ini" for output as #ini
print #ini, SourcePath$ '* write new source file and base path away
print #ini, BasePath$   '* not yet used
close #ini

'* print #main.SourceFilePath, "!contents? SourcePath$"
'* print #main.OutputFilesBasePath, "!contents? BasePath$"
open SourcePath$ for input as #Source
open BasePath$ + "\GoodDeclarations " + date$() + " " + str$(time$("seconds")) + ".txt" for output as #Declarations
open BasePath$ + "\MultiDeclarations " + date$() + " " + str$(time$("seconds")) + ".txt" for output as #MultiDeclarations
open BasePath$ + "\VariablesAndFunSubsUsed " + date$() + " " + str$(time$("seconds")) + ".txt" for output as #Variables
open BasePath$ + "\UndeclaredVariables " + date$() + " " + str$(time$("seconds")) + ".txt" for output as #UnDecVar
OpenFiles = True
[ExitOpenFiles]
End Function

Function GetLine()
'* InputLine$ left with comments, quotes and labels deleted. File lines are concatenated when joined
'* by "_" and separated when there are ":"s. False is returned when eof encountered, else True
'* Comment Lines,
'* First get a line if available, else exit

[TryAgain]
If (MoreLine = False) AND (eof(#Source) <> 0) goto [FailExit] '* as there is no more text

'* there must be text available from one or the other source
    If MoreLine = False then '* get a line from file plus any continuation
        line input #Source, InputLine$
        LineNum = LineNum + 1            '* Line numbers are counted as seen at the file level - matches Notepad++ use
        RawIL$ = InputLine$
        WHILE right$(InputLine$, 1) = "_"   '* there is a continuing line
           InputLine$ = left$(InputLine$, (len(InputLine$)-1))
           line input #Source, Var$ 
           LineNum = LineNum + 1
           InputLine$ = InputLine$ + Var$
        WEND
        '* now tidy this line from file
        InputLine$ = trim$(InputLine$)
        If (left$(InputLine$, 1) = "'") AND (left$(InputLine$, 4) <> "'Loc")  goto  [TryAgain] '* as this line is only a comment
        If (word$(InputLine$, 1) = "statictext")  goto  [TryAgain] '* as this line has neither declaration nor variables

        '* If there is a comment at the end of this line, discard it
        'Loc x
        InputLine$ = trim$(InputLine$)
        If instr(InputLine$, "'") > 2 then '* there is a 'later'* comment, so strip it off
            x = (instr(InputLine$, "'"))
            InputLine$ = left$(InputLine$, (x - 1))
            InputLine$ = trim$(InputLine$)
        end if
        '* Now deal with multi lines with ":" seperators
        'Loc sep
        sep = instr(InputLine$, ":")
        If  sep <> 0 then '* there is at least one ":"
            SavedLine$ = right$(InputLine$, len(InputLine$) - sep)
            InputLine$ = left$(InputLine$, sep - 1)
            MoreLine = True
        end if
    Else '* get a line from SavedLine
       If instr(SavedLine$, ":") = 0 then '* there is no more ":"s
          InputLine$ = SavedLine$
          SavedLine$ = ""
          MoreLine = False
       Else '* there is at least one more ":"
          InputLine$ = word$(SavedLine$, 1, ":")
          SavedLine$ = right$(SavedLine$, (len(SavedLine$) - len(InputLine$) - 1))
          MoreLine = True
       End If
    End if

'* Now eliminate some more irrelevances, firstly, multiple spaces
'Loc count, char$, charp1$
For count = 1 to len(InputLine$)
    char$ = mid$(InputLine$, count, 1)
    charp1$ = mid$(InputLine$, count+1, 1)
    If (char$ = " ") and (charp1$ = " ") then '* there is at least a double space
        InputLine$ = left$(InputLine$, count) + right$(InputLine$, len(InputLine$) - count -1)
    end if
next

'* * eliminate strings in "" (including the "")
'Loc start, finish, quote$
quote$ = chr$(34)
While instr(InputLine$, quote$) <> 0 '* a string is opened
    start = instr(InputLine$, quote$)
    finish = instr(InputLine$, quote$,  (start +1) )
    If finish <> 0 then '* the string is closed
        InputLine$ = left$(InputLine$, start - 1) + right$(InputLine$, len(InputLine$) - finish)
    else
        exit while '* case should not occur, but that's left to the compilor to flag
    end if
wend

'* Now eliminate 'goto lable'* 's
start = instr(InputLine$, "goto")
If start <> 0 then '* there is a goto
    finish = instr(InputLine$, "]")
    InputLine$ = left$(InputLine$, start - 1) + right$(InputLine$, len(InputLine$) - finish)
end if

'* Now eliminate lables
start = instr(InputLine$, "[")
If start <> 0 then '* there is a lable
    finish = instr(InputLine$, "]")
    InputLine$ = left$(InputLine$, start - 1) + right$(InputLine$, len(InputLine$) - finish)
end if

'* eliminate "print" and "open"  lines
start = instr(lower$(InputLine$), "print #")
If start <> 0 then '* there is a 'print'* line
    InputLine$ = ""
    goto [TryAgain]
end if
start = instr(lower$(InputLine$), "open ")
If start <>0 then '* there is an 'open'* line
    InputLine$ = ""
    goto [TryAgain]
end if

'* Have we anything left?
InputLine$ = trim$(InputLine$)
If len(InputLine$) = 0 goto [TryAgain]

'* Else we are finished, and with a 'true'* result
[TrueExit]
GetLine = True
Exit function
[FailExit]
GetLine = False
End Function

Sub SetVarType
'* This determines the current scope, & eliminates funsub declaration and end lines as they cannot contain a var
LCaseInputLine$ = trim$(lower$(InputLine$))
If word$(LCaseInputLine$, 1) = "function" then
    InputLine$ = right$(InputLine$, len(InputLine$) - 9)  '* Removes "function "
    FunSubName$ = word$(InputLine$, 1, "(")
    VarLoc$ = "is in Function"     '* Record that a Function has been entered and its name
    InputLine$ = ""
End If

If word$(LCaseInputLine$, 1) = "sub" then
    InputLine$ = right$(InputLine$, len(InputLine$) - 4) '* Removes "sub "
    FunSubName$ = word$(InputLine$, 1)
    VarLoc$ =  "is in Subroutine" '* Record that a Subroutine has been entered and its name
    InputLine$ = ""
End If

'* Now look to see if we have exited a FunSub
If (word$(LCaseInputLine$, 1) = "end") AND_
    ((word$(LCaseInputLine$, 2) = "sub") OR_
    (word$(LCaseInputLine$, 2) = "function")) then
        VarLoc$ = "is Outside all FunSub"
        FunSubName$ = "Global"
        InputLine$ = ""
End if

End Sub '* SetVarType



'*********************************************************************************************************
'* END OF FUNCTIONS / SUBROUTINES WHICH ONLY DO INPUT FILE HANDLING
'*********************************************************************************************************

'**********************************************************************************************
'* FUNCTIONS / SUBROUTINES WHICH ONLY DO INPUT LINE HANDLING
'**********************************************************************************************

Function ThereIsArrayDec()
 '* Each iteration removes (L to R) a declared array name from "InputLine$" & stores it in "Token$". The line then has Dim re-inserted.
'Loc temp$
ThereIsArrayDec = False
InputLine$ = trim$(InputLine$)
LCaseInputLine$ = lower$(InputLine$)
If word$(LCaseInputLine$, 1) = "rdim" then
    InputLine$ = ""
    GoTo [ExitTIAD]
End If
If word$(LCaseInputLine$, 1) = "dim" then
    ThereIsArrayDec = True
    TypeOfDec$ = "is an Array"
    InputLine$ = right$(InputLine$, len(InputLine$) - 4) '* Remove "dim "
    Token$ = word$(InputLine$, 1, "(")                '* get the first array name
    temp$ = word$(InputLine$, 1, ")")
    InputLine$ = right$(InputLine$, len(InputLine$) - len(temp$)-2) '* This strips off up to & including ")" and a following ","
    '* InputLine$ is now either empty (only one array declared), or has a possible space followed by array(s)
    InputLine$ = trim$(InputLine$)
    If len(InputLine$) <= 0 GoTo [ExitTIAD]
    InputLine$ = "Dim " + InputLine$
End If
[ExitTIAD]
End Function     '* ThereIsArrayDec

Function ThereIsDec()
'* This function identifies a single declaration & its type - if there are any in the input line - & deletes that
'* token from the input line. There may be multi declarations in a line, but the three types of declaration are mutually
'* exclusive within a line, so the whitling down of a line by one of the three does not introduce errors into the other two.
If len(InputLine$)= 0 goto  [ExitTID] '* an empty or exhausted line

'* First deal with sub and function declarations including their local parameter(s) (the "(s)" is significant!)
'* The limited scope of the parameters is identified, but the funsubs name is treated as  a special type of Global declaration. "Token$", "TypeOfDec$", "CurrentFunSub$", and "FunSubName$ are all set if new values found.
'* Record when we enter and leave a FunSub
ThereIsDec = False
If FunSubDec() = True then
    ThereIsDec = True
    goto [ExitTID]
End if

'* Now look for local declarations.
'**************************************
'* "Token$", and "TypeOfDec$" are set if new values found.
If LocalDec() = True then
    ThereIsDec = True
    goto [ExitTID]
End if

'* Now look for global declarations.
'*****************************************
'* "Token$", and "TypeOfDec$" are set if new values found.
If GlobalDec() = True then
    ThereIsDec = True
End if

[ExitTID]
End Function '* ThereIsDec

Function FunSubDec()
'* "Token$", "TypeOfDec$", "CurrentFunSub$", and "FunSubName$" are all set if new values found.
FunSubDec = False
'Loc Name$, LeftNum
InputLine$ = trim$(InputLine$)
LCaseInputLine$ = lower$(InputLine$)
If word$(LCaseInputLine$, 1) = "function" then
    '* First recognise the function name as a declaration
    InputLine$ = right$(InputLine$, len(InputLine$) - 9)'* Removes "function "
    Token$ = word$(InputLine$, 1, "(")
    If Token$ <> "aZ!@#" then '* the function name has not yet been recorded, so Token$ is valid and should be passed on to
        '* be put on the DecArray. Otherwise go look for parameter declarations.
        TypeOfDec$ = "is a Function"
        InputLine$ = "Function aZ!@#" + right$(InputLine$, len(InputLine$) - len(Token$))
        CurrentFunSub$ = "Function, " + Token$ '* Record that a Function has been entered and its name
        FunSubName$ = Token$
        FunSubDec = True
        goto [ExitFSD]
    End If
    '* As this was not the first pass of this line the Function name has been saved  into the DecArray
    '* - so check for parameter declarations
    If instr(InputLine$, "()") <> 0 goto [ExitFSD] '* as there are no parameters
    InputLine$ = trim$(InputLine$)
    LeftNum = instr(InputLine$, "(")
    Name$ = left$(InputLine$, LeftNum)
    InputLine$ = right$(InputLine$, len(InputLine$) - LeftNum)   'strip off the word "function", "aZ!@#", & "("
    If instr(InputLine$, ",") = 0 then '* we just have one Token left in this line
        Token$ = InputLine$
        If right$(Token$,1) = ")" then
            Token$ = left$(Token$, len(Token$) -1)
        end If
        InputLine$ = ""
    else '* there is a comma
        Token$ = word$(InputLine$, 1, ",") 'the first 'word'* is a token
        InputLine$ = trim$(right$(InputLine$, len(InputLine$) - len(Token$) - 1))'strip off the token and ","
        InputLine$ = "function " + Name$ + InputLine$  '* Leaves the line ready for the next pass
    end if
    TypeOfDec$ =  "is a parameter of Function"
    FunSubName$ = trim$(word$(CurrentFunSub$, 2, ","))
    Token$ = trim$(Token$)
    FunSubDec = True
    goto [ExitFSD]
End If

'*  Start Sub
InputLine$ = trim$(InputLine$)
LCaseInputLine$ = lower$(InputLine$)
If word$(LCaseInputLine$, 1) = "sub" then
    '* First recognise the subroutine name as a declaration
    InputLine$ = right$(InputLine$, len(InputLine$) - 4) '* Removes "sub "
    Token$ = word$(InputLine$, 1)
    If Token$ <> "#Z!@" then
        '* the subroutine name has not yet been recorded, so Token$ is valid and should be put on
        '* the DecArray. Otherwise go look for parameter declarations.
        TypeOfDec$ = "is a Subroutine"
        InputLine$ = "sub " + "#Z!@" + right$(InputLine$, len(InputLine$) - len(Token$))
        CurrentFunSub$ =  "Subroutine, " + Token$    '* Record that a Subroutine has been entered and its name
        FunSubName$ = Token$
        FunSubDec = True
        goto [ExitFSD]
    End if
    '* As this was not the first pass of this line the Sub name has been saved already in the DecArray
    '* Declaration SUB name dealt with - so check for parameter declarations
    InputLine$ = trim$(right$(InputLine$, len(InputLine$) - 5)) '* Removes "#Z!@ " - "sub" removed previously
    Token$ = word$(InputLine$, 1, ",")    '* Token$ is the first parameter declaration - may be blank
    TypeOfDec$ = "is a parameter of Subroutine"
    FunSubName$ = trim$(word$(CurrentFunSub$, 2, ","))
    If Token$ = "" goto [ExitFSD]       '* FunSubDec is False, Token$ is empty. Else setup InputLine$ to check for more
    InputLine$ = "sub #Z!@ " + right$(InputLine$, len(InputLine$) - len(Token$) - 1)
    Token$ = trim$(Token$)
    FunSubDec = True
end If

'* Now look to see if we have exited a FunSub
If (word$(LCaseInputLine$, 1) = "end") AND_
    ((word$(LCaseInputLine$, 2) = "sub") OR_
    (word$(LCaseInputLine$, 2) = "function")) then
    CurrentFunSub$ = ""
    FunSubName$ = "Global"
    TypeOfDec$ = ""
End if
[ExitFSD]
End Function '*FunSubDec

Function LocalDec()
'* "Token$" and "TypeOfDec$", are set if new values found.
InputLine$ = trim$(InputLine$)
LocalDec = False
If (left$(InputLine$, 4)= "'Loc") then '* Keyword is only valid @ start of a trimmed line
    TypeOfDec$ = "is a Local"
    InputLine$ = trim$(right$(InputLine$,(len(InputLine$) - 4)))  '* strip off the "'Loc"
    '* Four situations to untangle: An empty Line | Token<LF> | Token, NextToken(s)<LF>  |  Token,NextToken(s)<LF>
    If len(InputLine$) = 0 goto [ExitLD]
    LocalDec = True
    If instr(InputLine$, ",") = 0 then '* we just have one Token left in this line
        Token$ = InputLine$
        InputLine$ = ""
        goto [FSTest]
    else '* there is a comma
        Token$ = word$(InputLine$, 1, ",") '* the first 'word' is a token
        InputLine$ = "'Loc " + right$(InputLine$,(len(InputLine$) - len(Token$) - 1)) '* "-1" for the comma
    end if
    Token$= trim$(Token$)
[FSTest]
     '* A Token has been found - is it inside a FunSub or not?
    If CurrentFunSub$ = "" goto  [ExitLD]   '* as we are not in a FunSub so no special processing is required
'* We are in a funsub so the 'Loc is for a funsub local so need to set TypeOfDec$ appropriately
    If word$(CurrentFunSub$, 1, ",") = "Function" then
        TypeOfDec$ = "is a local to Function"
    Else
        TypeOfDec$ = "is a local to Subroutine"
    End If

    FunSubName$ = word$(CurrentFunSub$, 2, ",")
    If left$(InputLine$, 1) = "'"  goto  [ExitLD] '* rest of line is comment
    If len(InputLine$) = 0 goto [ExitLD] '* last token has been found - else . . .
    InputLine$ = "'Loc " + InputLine$ '* this allows another Token to be recognised next call
End If

[ExitLD]
End Function '*LocalDec

Function GlobalDec()
'* "global" is recognised as a declaration irrespective of its case, but declared
'* variable(s) are case sensitive.
'* "Token$" and "TypeOfDec$", are set if new values found.
'Loc lenIL
GlobalDec = False
If word$(LCaseInputLine$, 1) = "global" then
        TypeOfDec$ = "is a Global"
        GlobalDec = True
        InputLine$ = trim$(InputLine$)
         lenIL = len(InputLine$)
        InputLine$ = right$(InputLine$, lenIL - 6) 'strip off the "global"
    '* Three situations to untangle: Token<LF> | Token, NextToken(s)<LF>  |  Token,NextToken(s)<LF>
    If instr(InputLine$, ",") = 0 then '* we just have one Token left in this line
        Token$ = InputLine$
        InputLine$ = ""
    else '* there is a comma
        Token$ = word$(InputLine$, 1, ",") '*  the first 'word'* is a token
        InputLine$ = right$(InputLine$,(len(InputLine$) - len(Token$) - 1))
    end if
    InputLine$ = trim$(InputLine$)
    Token$= trim$(Token$)
    If len(InputLine$) = 0 goto [ExitGD] '* last token has been found
    InputLine$ = "global " + InputLine$ '* this allows another Token to be recognised next call
end if
[ExitGD]
End Function '* GlobalDec

Function ThereIsVar()
'* **********************************************************************************************
'* Steps to resolve vars in the input line:

'* 1 scan the line for "~". The word before and the word after are tokens - possible vars.
'* 2 Test the  tokens for 'varness'
'* 3 If var found, reset line for the external loop, if not, resume scanning the line

'* Since what remains can contain multiple vars, then finding one and exiting with
'*  "ThereIsVar" =  True is OK if provision is made so that re-entry here is coped with.
'* However if a token is found that turns out not to be a var, then this function must continue to
'* search this line for tokens, and test for 'varness'

'* **********************************************************************************************
Token$  = ""
ThereIsVar = False

If InputLine$ = "" goto [ExitTIV]
While LookForOneToken() = True      '* Scan InputLine$ for possible tokens that may be vars. This is step 1
    If TokenTest() = True then        '* There is a Var - this is step 2
        ThereIsVar = True
        Exit While
    Else
        '* TokenTest failed so set InputLine so it starts with "~". Note if the token was from the start of a
        '* line it needs a "~" adding, else it's already there
        InputLine$ = "~" + trim$(InputLine$)
        Call Substitute "~", "~~", InputLine$
        Token$ = ""
    End If
Wend
[ExitTIV]
End Function '* ThereIsVar

Function LookForOneToken()
'* First scan for "~". The word before and the word after may be Token.
'* If a Token, which may be a var, is found reset the line to allow for a further search and exit from here.
'Loc char$, charm1$, Front$, PossibleVar, len1, len2, count
LookForOneToken = False
InputLine$ = trim$(InputLine$)
For count = 1 to len(InputLine$)
    char$ = mid$(InputLine$, count, 1)
    charm1$ = mid$(InputLine$, count - 1, 1)
    If (char$ = "~") AND (count > 1) then '* there is room for a Token before the "~" but there may be a "for", "while" or "if" ... first.
        Front$ = left$(InputLine$, instr(InputLine$, "~") - 1) '* "- 1" to ditch the "~"
        Front$ = trim$(Front$) '* get rid of any space(s) just before the "~"
        While instr(Front$, " ") <> 0       '* There must be a space after a "while" or an "if" so strip off until there is only -
            Front$ = right$(Front$, len(Front$) - instr(Front$, " "))   '* - the one token before the "~"
        Wend
        Token$ = word$(Front$, 1, "~")
         '* There can be no "~" before a token at the begining of a line, so add one ready for the next loop
        InputLine$ = "~" + trim$(right$(InputLine$, len(InputLine$) - count))
        goTo [Found]
    End If
    If (char$ = "~") and (count = 1) then '* there is no Token before the "~", but there could be one or more after
        InputLine$ = right$(InputLine$, len(InputLine$) - 1) '* strip off the "~"
        InputLine$ = trim$(InputLine$)
        If len(InputLine$) > 0 then '* there may be one or more following Token
            len1 = instr(InputLine$, "~")
            If len1 = 0  then  '* There is text but no "~". So there is either a single word token or no token
                len2 = instr(InputLine$, " ")
                If len2 > 0 GoTo [ExitLFOT]'* there is more than one word, so there is no token
                Token$ = InputLine$         '* there are no spaces so the whole line is a token
                LookForOneToken = True
                InputLine$ = ""
                goTo [Found]
            Else '* there is text that contains a "~"
                Token$ = trim$(word$(InputLine$, 1, "~"))
                '* There has to be a "~" after token, so we don't need to add one ready for the next loop
                InputLine$ = trim$(right$(InputLine$, len(InputLine$) - len(Token$))) '* Leave the "~" ready for the next loop
                GoTo [Found]
            End If
        Else
            GoTo [ExitLFOT]     '* No line left
        End If
    End If
Next
GoTo [ExitLFOT]

[Found]
While instr(InputLine$, "~~") <> 0
    Call Substitute "~", "~~", InputLine$
Wend
While instr(InputLine$, "  ") <> 0
    Call Substitute " ", "  ", InputLine$
Wend
While instr(InputLine$, "~ ~") <> 0
    Call Substitute "~", "~ ~", InputLine$
Wend
Token$ = trim$(Token$)
LookForOneToken = True

[ExitLFOT]
End Function '* LookForOneToken

Sub VarPrePass
'*  This preconditions the input line once, prior to the iterative search for vars.
'* 1.1 Eliminate lines that cannot hold a var.
'* 1.15 Do all of section 1.3 in the introduction
'*  1.17 Do all of section 2 in the introduction
'* 1.2 Deal with "for .. step .." lines
'* 1.3 look for "and", "or", "not" and replace by "~"
'* 1.4 replace each of | <, <=, >, >=, =, <>, +, -, *, /, ^ , ","| by a single place holder "~"
'* 1.5 tidy the multiple spaces etc. that may have been introduced


'Loc name$, count, position, position2, front$
'*  Step 1.1 - eliminate "global", "'Loc", "dim", "rdim", "sub" and "function" lines
LCaseInputLine$ = lower$(InputLine$)
If (instr(LCaseInputLine$, "global ") + instr(InputLine$, "'Loc ") + instr(LCaseInputLine$, "dim ") +_
 instr(LCaseInputLine$, "sub ") + instr(LCaseInputLine$, "function"))<> 0 then
    InputLine$ = ""     '* Step 1.1 done
    GoTo [ExitVPP]
end if

'* 1.15 - deal with parentheses per introductory section 1.3.
[WhileLoopA]     '* Just to avoid a long indent
While instr(InputLine$, "~~") <> 0
    Call Substitute "~", "~~", InputLine$
Wend
While instr(InputLine$, "  ") <> 0
    Call Substitute " ", "  ", InputLine$
Wend
While instr(InputLine$, "~ ~") <> 0
    Call Substitute "~", "~ ~", InputLine$
Wend
position = instr(InputLine$, "(")
If position = 0 goto [StepOneDotTwo] '* an opening parenthesis does not exist in this line, so skip on to step 1.2

'* First find the 'name' in front of the "(" for all the section 1.3 steps
For position2 = position to 1 step -1
    If mid$(InputLine$, position2, 1) = " " then
        exit for
    End If
next
If position2 = 0 then position2 = 1    '* This deals with the 'name' being at the begining of a line, no space found.
name$ = trim$(mid$(InputLine$, position2, position - position2))

'* '* Check for native functions (Section 1.3's step A1). There is a long list of these in LB - they are all to be deleted from this line.
'Loc t$, x
t$ = lower$(name$)    '* Just to shorten this text, and include both cases!
x = (t$ = "abs") OR (t$ = "acs") OR (t$ = "as") OR (t$ = "asc") OR (t$ = "asn") OR_
(t$ = "atn") OR (t$ = "chr$") OR (t$ = "cos")OR (t$ = "chr$") OR (t$ = "date$") OR _
(t$ = "dechex$")OR (t$ = "dim") OR (t$ = "eof") OR (t$ = "exp")OR_
(t$ = "eval")OR (t$ = "hbmp") OR (t$ = "hexdec") OR (t$ = "hwnd") OR_
(t$ = "if") OR (t$ = "inp")OR (t$ = "input$") OR (t$ = "inputto$") OR (t$ = "instr") OR_
(t$ = "int") OR (t$ = "left$") OR (t$ = "len") OR (t$ = "lof") OR (t$ = "log") OR_
(t$ = "lower$") OR (t$ = "max")OR (t$ = "mid$") OR (t$ = "midipos") OR_
(t$ = "min") OR (t$ = "mkdir") OR (t$ = "open") OR (t$ = "right$") OR (t$ = "rmdir") OR_
(t$ = "rnd") OR (t$ = "sin") OR (t$ = "space$")OR (t$ = "sqr") OR (t$ = "str$") OR_
(t$ = "tab") OR (t$ = "tan")OR (t$ = "time$")OR (t$ = "trim$")OR (t$ = "txcount") OR_
(t$ = "upper$") OR (t$ = "using") OR (t$ = "val ") OR (t$ = "word$")

If x = True then    '* name$ is a native function - but it may also occur within other text in the line! front$
    front$ = word$(InputLine$, 1, ")") '* this gives us everything up to but excluding the first ")"
    InputLine$ = right$(InputLine$, len(InputLine$) - len(front$)-1)  '* this removes front$ and ")" from InputLine$
    name$ = name$ + "("
    Call Substitute "", name$, front$ '* delete the native function name
    While instr(front$, ",") <> 0
        Call Substitute "~", ",", front$
    Wend
    front$ = front$ + "~"
    InputLine$ = front$ + InputLine$
    GoTo [WhileLoopA]    '* As a native function sucessfuly found and dealt with - GoTo just to avoid a long indent
End If

'* Native function not found so look for a call to a declared function (Step 1.3 A.2 in the introduction)
'Loc DecName$
For count = 1 to DecEndPointer - 1
    DecName$ = word$(DecArray$(count), 1, ",")
    If instr(InputLine$, DecName$) <> 0  then '* this function name is in the input line at least once
        front$ = word$(InputLine$, 1, ")") '* this gives us everything up to but excluding the first ")"
        InputLine$ = right$(InputLine$, len(InputLine$) - len(front$)-1)  '* this removes front$ and ")" from InputLine$
        Call Substitute "", name$, front$ '* delete the native function name
        Call Substitute "~", "(", front$
        While instr(front$, ",") <> 0
            Call Substitute "~", ",", front$
        Wend
        front$ = front$ + "~"
        InputLine$ = front$ + InputLine$
        GoTo [WhileLoopA]    '* As a declared function sucessfuly found and dealt with - GoTo just to avoid a long indent
    End If
Next

'* Declared function not found so look for a use of a declared array (Step 1.3 A.3 in the introduction)
'Loc ArrayName$
For count = 1 to ArrayArrayEndPointer - 1
    ArrayName$ = word$(ArrayArray$(count), 1)
    If instr(InputLine$, ArrayName$) <> 0 then '* this array name is in the input line at least once
        Call Substitute "", name$,  InputLine$  '* This deletes the array name, but leaves the "(...)"
        position = instr(InputLine$, "(")
        position2 = instr(InputLine$, ")")  '* This allows dumping the "(. . .)"
        InputLine$ = left$(InputLine$, position - 1) + right$(InputLine$, len(InputLine$)- position2)
        GoTo [WhileLoopA]     '* As a declared array sucessfuly found and dealt with - GoTo just to avoid a long indent
    End If
Next

'* which leaves any "(...)" which leaves undeclared functions or arrays! ((Step 1.3 A.4 in the introduction)
'* First add 'name' to the Var array - if it is a valid name.
Token$ = name$   '* since TokenTest only tests Token$
If TokenTest() = True then
    If VarEndPointer >= BigArraySize goto [FailExitTFF]
    VarArray$(VarEndPointer) = name$ + ", 'is an undeclared array or function in line, " + str$(LineNum)
    VarEndPointer = VarEndPointer + 1
End If
'* now do the usual name delete and "~"'ing
front$ = word$(InputLine$, 1, ")") '* this gives us everything up to but excluding the first ")"
InputLine$ = right$(InputLine$, len(InputLine$) - len(front$)-1)  '* this removes front$ and ")" from InputLine$
Call Substitute "", name$, front$ '* delete the array / function name
Call Substitute "~", "(", front$
While instr(front$, ",") <> 0
    Call Substitute "~", ",", front$
Wend
front$ = front$ + "~"
InputLine$ = front$ + InputLine$

GoTo [WhileLoopA]     '*  As all section 1.3 cases dealt with - GoTo just to avoid a long indent

[StepOneDotTwo]
While instr(InputLine$, "~~") <> 0
    Call Substitute "~", "~~", InputLine$
Wend
While instr(InputLine$, "  ") <> 0
    Call Substitute " ", "  ", InputLine$
Wend
While instr(InputLine$, "~ ~") <> 0
    Call Substitute "~", "~ ~", InputLine$
Wend

'* step 1.2, Deal with "for .. step .." lines
position = instr(lower$(InputLine$), "for")
If position <> 0 then '* there is a "for ... to ... step" statement
    Call SubstituteC "~", " for ", InputLine$
    Call SubstituteC "~", " to ", InputLine$
    Call SubstituteC "~", " step ", InputLine$
End If

'* step 1.3, look for "byref", "and", "or", "not" and replace by "~" - deal with calls
Call SubstituteC "~", " and ", InputLine$  '* these four words cannot (legally) ocur at the begining of a line,
Call SubstituteC "~", "byref ", InputLine$
Call SubstituteC "~", " or ", InputLine$
Call SubstituteC "~", " not ", InputLine$
If trim$(word$(lower$(InputLine$), 1)) = "call" then
    Call SubstituteC "~", "call ", InputLine$   '* "call" can ocur at the begining of a line.
    Call Substitute "~", " ", InputLine$        '* replace any spaces between parameters by "~"
End If

'* step 1.4, replace each of | <, <=, >, >=, =, <>, +, -, *, /, ^ , ","| by a single place holder "~"

'Loc char$, charp1$
For count = 1 to len(InputLine$)
    char$ = mid$(InputLine$, count, 1)
    If ((char$ = "<") OR (char$ = ">") OR (char$ = "=") OR (char$ = "+") OR (char$ = "-") OR (char$ = "*")_
        OR (char$ = "/") OR (char$ = "^") OR (char$ = ",")) then
        InputLine$ = left$(InputLine$, count -1) + "~" + right$(InputLine$, len(InputLine$) - count) '* This may leave spaces
    end if
next
For count = 1 to len(InputLine$)
    char$ = mid$(InputLine$, count, 1)
    charp1$ = mid$(InputLine$, count+1, 1)
    If (char$ = "~") and ((charp1$ = "=") or (charp1$ = ">")) then
        InputLine$ = left$(InputLine$, count) + "~" + right$(InputLine$, len(InputLine$) - count -1)
    end if
next

'* Step 1.5 tidy the multiple spaces etc. that may have been introduced
While instr(InputLine$, "~~") <> 0
    Call Substitute "~", "~~", InputLine$
Wend
While instr(InputLine$, "  ") <> 0
    Call Substitute " ", "  ", InputLine$
Wend
While instr(InputLine$, "~ ~") <> 0
    Call Substitute "~", "~ ~", InputLine$
Wend
[ExitVPP]
End Sub '* VarPrePass


Sub Substitute NewString$, OldString$, ByRef InString$
'* If Oldstring$ is found exactly as input, it is replaced by NewString$
'* If OldString is not found, exit with no change to InString$
'Loc position
position = instr(InString$, OldString$)
If position = 0 goto [ExitS]
InString$ = left$(InString$, position - 1) + NewString$ + right$(InString$, len(InString$) - position - len(OldString$) + 1)
[ExitS]
End Sub '* Substitute

Sub SubstituteC NewString$, OldString$, ByRef InString$
'* If Oldstring$ of any case is found it is replaced by NewString$
'* If OldString$ is not found, exit with no change to InString$
'Loc position, LCIS$
LCIS$ = lower$(InString$)
OldString$ = lower$(OldString$)
position = instr(LCIS$, OldString$)
If position = 0 goto [ExitS]   '* OldString$ not present at any case
InString$ = left$(InString$, position - 1) + NewString$ + right$(InString$, len(InString$) - position - len(OldString$) + 1)
[ExitS]
End Sub '* SubstituteC

Function TokenTest()
'* There is a token which is a possible var - so now it has to be subjected to various tests. If it fails then
'* the psuedo token must be removed from the line, "~" inserted and the process iterated unless the line is empty.
TokenTest = False
'* Does it start with an alpha?
'Loc ascT
ascT = asc(Token$)
If NOT(((ascT > 64) and (ascT < 91))OR ((ascT > 96) and (ascT < 123))) then
    GoTo [ExitTT]   '* as Token does not start with an alpha
End If

'* Does it contain a 'special' character? - But "$" at the end of a token is OK
'Loc T$
T$ = Token$
While len(T$) > 1   '* test up to, but excluding the last character
    ascT = asc(T$)
    If ((ascT > 33) and (ascT < 47)) OR ((ascT > 58) and (ascT < 64)) OR_
        ((ascT > 91) and (ascT < 96)) OR (ascT >122) then
        GoTo [ExitTT]    '* as Token contains a special character
    Else
        T$ = right$(T$, len(T$) - 1) '* Strip of te first character each iteration
    End If
Wend
ascT = asc(T$)
If T$ = "$" goto [Keywords]   '* as a "$" at the end is ok
If ((ascT > 33) and (ascT < 47)) OR ((ascT > 58) and (ascT < 64)) OR_
        ((ascT > 91) and (ascT < 96)) OR (ascT >122) _
        GoTo [ExitTT]    '* as the last character is a special character and not "$"

[Keywords]
'* There is a very long list of recognised keywords in LB - they are all excluded from being variable names.
'Loc t$, x
t$ = lower$(Token$)
x = (t$ = "abs") OR (t$ = "acs") OR (t$ = "as") OR (t$ = "and") OR (t$ = "asc") OR (t$ = "asn") OR_
(t$ = "atn") OR (t$ = "beep") OR (t$ = "bmpbutton") OR (t$ = "bmpsave") OR_
(t$ = "button") OR (t$ = "byref") OR (t$ = "call") OR (t$ = "case") OR_
(t$ = "callback") OR (t$ = "calldll") OR  (t$ = "checkbox") OR (t$ = "chr$") OR_
(t$ = "chr$") OR (t$ = "cls") OR (t$ = "colordialog") OR (t$ = "combobox") OR_
(t$ = "commandline$") OR (t$ = "confirm") OR (t$ = "cos") OR (t$ = "cursor")

x = x  OR (t$ = "data") OR (t$ = "date$") OR (t$ = "dechex$") OR (t$ = "defaultdir$") OR_
(t$ = "dim") OR (t$ = "displaywidth") OR (t$ = "displayheight") OR (t$ = "do") OR_
(t$ = "drives$") OR (t$ = "dump") OR (t$ = "else") OR (t$ = "end") OR_
(t$ = "eof") OR (t$ = "error") OR (t$ = "exit") OR (t$ = "exp")

x = x OR (t$ = "eval") OR (t$ = "field") OR (t$ = "filedialog") OR (t$ = "files") OR_
(t$ = "fontdialog") OR (t$ = "for") OR (t$ = "function") OR (t$ = "get") OR_
(t$ = "gettrim ") OR (t$ = "gosub") OR (t$ = "global") OR (t$ = "goto")

x = x OR (t$ = "graphicbox") OR (t$ = "groupbox ") OR (t$ = "hbmp") OR (t$ = "hexdec") OR_
(t$ = "hwnd") OR (t$ = "if") OR (t$ = "inkey$") OR (t$ = "inp")

x = x OR (t$ = "input") OR (t$ = "input$") OR (t$ = "inputto$") OR (t$ = "instr") OR_
(t$ = "int") OR (t$ = "kill s$") OR (t$ = "left$") OR (t$ = "len") OR_
(t$ = "let") OR (t$ = "line input") OR (t$ = "listbox") OR (t$ = "loadbmp") OR_
(t$ = "locate") OR (t$ = "lof") OR  (t$ = "log") OR (t$ = "loop") OR_
(t$ = "lower$") OR (t$ = "lprint") OR (t$ = "mainwin") OR (t$ = "max")

x = x OR (t$ = "maphandle") OR (t$ = "menu") OR (t$ = "mid$") OR (t$ = "midipos") OR_
(t$ = "min") OR (t$ = "mkdir") OR (t$ = "mod") OR (t$ = "name") OR_
(t$ = "next") OR  (t$ = "nomainwin") OR (t$ = "notice") OR (t$ = "on") OR_
(t$ = "oncomerror") OR (t$ = "open") OR (t$ = "out") OR (t$ = "or") OR (t$ = "platfOR_m$") OR_
(t$ = "playmidi") OR (t$ = "playwave") OR (t$ = "popupmenu")

x = x OR (t$ = "print") OR (t$ = "printerdialog") OR (t$ = "prompt") OR (t$ = "put") OR_
(t$ = "radiobutton") OR (t$ = "randomize") OR (t$ = "read") OR (t$ = "readjoystick") OR_
(t$ = "redim") OR (t$ = "rem") OR (t$ = "refresh") OR (t$ = "resizehandler")

x = x OR (t$ = "restORe") OR (t$ = "resume") OR (t$ = "return") OR (t$ = "right$") OR_
(t$ = "rmdir") OR (t$ = "rnd") OR (t$ = "run s$") OR (t$ = "scan") OR_
(t$ = "seek") OR (t$ = "select") OR (t$ = "sin") OR (t$ = "sOR_t") OR (t$ = "space$")

x = x OR (t$ = "sqr") OR (t$ = "statictext") OR (t$ = "stop") OR (t$ = "stopmidi") OR (t$ = "str$") OR_
(t$ = "struct") OR (t$ = "stylebits") OR (t$ = "sub") OR (t$ = "tab") OR (t$ = "tan")

x = x OR (t$ = "textbox") OR  (t$ = "textboxcolor$") OR (t$ = "then") OR (t$ = "time$")

x = x OR (t$ = "timer") OR (t$ = "titlebar") OR (t$ = "trace") OR (t$ = "trim$")

x = x OR (t$ = "txcount") OR (t$ = "unloadbmp") OR (t$ = "upper$") OR (t$ = "using") OR_
(t$ = "upperleftx") OR  (t$ = "upperlefty") OR (t$ = "val ") OR  (t$ = "version$ ")

x = x OR (t$ = "wait") OR  (t$ = "wend") OR (t$ = "while") OR  (t$ = "windowwidth") OR (t$ = "windowheight") OR_
(t$ = "winstring") OR (t$ = "word$") OR (t$ = "xor")

If x = False then '* All tests passed
    TokenTest = True
end if
[ExitTT]
End function '* TokenTest

'*************************************************************************************************
'* END OF FUNCTIONS / SUBROUTINES WHICH DO INPUT LINE HANDLING
'*************************************************************************************************

'*******************************************************************************
'* FUNCTIONS / SUBROUTINES WHICH HANDLE THE ARAYS
'********************************************************************************

Sub AddArrayDec
'* Token is added to the ArrayArray$ unless it is already there - duplication is ignored
If ArrayArrayEndPointer >= BigArraySize goto [FailExitAAD]
'* else add Token$ to the array array
ArrayArray$(ArrayArrayEndPointer) = "Array " + Token$ + " declared in line " + str$(LineNum)
ArrayArrayEndPointer = ArrayArrayEndPointer + 1
goto [NormalExitAAD]
[FailExitAAD]
'Add Token failed, so
notice "Fatal Error!" + chr$(13) + "Adding an Array to the ArrayArray failed"
goto [quit]
[NormalExitAAD]
End Sub '*  AddArrayDec


Sub TokenFiFo DecVar$   '* First in - First out (Queue)
'* This subroutine handles two queues, one for declarations and one for variables. Dec is
'* expected to be True if a declaration operation is required, else a 'variable'* operation
'* is assumed.
'* s$ is added to the appropriate queue. If the identified queue is full on entry,
'* a failure exit from the program is made.
'* There is no need to circularise the buffer since only additions are made, and only the end pointer
'* is of interest on inputs. However both pointers are of interest when copying entries to files.
'* The subroutine also identifies which line the token is encountered in.
If DecVar$ ="Dec" then
    If DecEndPointer >= BigArraySize goto [FailExitTFF]
    '* else add item to declaration array
    If ((TypeOfDec$ = "is an Array") OR (TypeOfDec$ = "is a Local") OR (TypeOfDec$ = "is a Global") OR_
                            (TypeOfDec$ = "is a Function") OR (TypeOfDec$ = "is a Subroutine")) then
        DecArray$(DecEndPointer) = Token$ + ", " + TypeOfDec$ + ", " + "-" + "," + " is NOT Used,"+_
                                     " and is Declared in line" + ", " + str$(LineNum) + ", " + " -"
    Else
        DecArray$(DecEndPointer) = Token$ + ", " + TypeOfDec$ + ", " + FunSubName$ + ", " + " is NOT Used,"+_
                                    " and is Declared in line" + ", " + str$(LineNum) + ", " + " -"
    End If
    DecEndPointer = DecEndPointer + 1
else '* must be a variable
    If VarEndPointer >= BigArraySize goto [FailExitTFF]
    '* else add s$ to variable array - knowing it is not already in the queue
    VarArray$(VarEndPointer) = Token$ + ", " + VarLoc$ + ", " + FunSubName$ + ", " + "Used"_
                                    + ", " + "1" + ", " + "times - eg in line" + ", " + str$(LineNum) + "," + "-"
    CurrentVarArrayPtr = VarEndPointer
    VarEndPointer = VarEndPointer + 1
end if '* done with inputs
goto [NormalExitTFF]

[FailExitTFF]
'Add Token failed, so
notice "Fatal Error!" + chr$(13) + "Adding Var or Dec to array failed"
goto [quit]
[NormalExitTFF]
End Sub '* TokenFiFo

Function TokenInDecList()
'* This function returns "True" if the Token$ / TypeOfDec$ / Subname$ triplet are matched by an existing entry. However since a "Loc outside
'* funsubs and a global are equivalent to LB, these are flagged as a scope issue, and similarly if a funsub local and global level declaration
'* have the same name.

TokenInDecList = False
'Loc count, w1$, w2$, w3$, SubName$
SubName$ = trim$(word$(CurrentFunSub$, 2, ","))

OverlappingDeclarations = False
for count = DecStartPointer + 1 to DecEndPointer - 1 step 1
    w1$ = trim$(word$(DecArray$(count), 1,","))  '*  <token name>
    w2$ = trim$(word$(DecArray$(count), 2,","))  '* This is the type of the item, e.g. Global, Function ...
    w3$ = trim$(word$(DecArray$(count), 3,","))  '* This is either a "-" or a funsub name

    If Token$ = w1$ then    '* it may be in the Dec List since the token's name is in the DecArray$.. . .
        Select case  TypeOfDec$ 
            case "is an array"        '* Multiple array declarations have already been checked for.
                goto [TNIDLExit]        '* As any othe match is not a clash
            case "is a Local", "is a Global"    '* So it is not allowed to clash with anything
                If     (    ((w2$ = "is a Local") AND (TypeOfDec$ = "is a Local")) OR_
                        ((w2$ = "is a Global") AND (TypeOfDec$ = "is a Global")) _
                    ) then
                    goto [TNIDLTrueExit]  '* As this is a multi dec within a scope
                end if
                If     (    (w2$ = "is an Array") OR_
                        (w2$ = "is a Local") OR_
                        (w2$ = "is a Global") OR_
                        (w2$ = "is a Function") OR_
                        (w2$ = "is a Subroutine") OR_
                        (w2$ = "is a local to Function") OR_
                        (w2$ = "is a parameter of Function") OR_
                        (w2$ = "is a local to Subroutine") OR_
                        (w2$ = "is a parameter of Subroutine")_
                    ) then
                    OverlappingDeclarations = True '* As this is a multi dec considered to be in 'differing' scopes
                    goto [TNIDLTrueExit]
                end if
            case "is a Function"        '* Can clash with anything except another function
                If (w2$ = "is a Function") then
                    goto [TNIDLTrueExit]  '* As this is a multi dec in the global scope
                end if
            case "is a Subroutine"    '* Can clash with anything except another subroutine
                If (w2$ = "is a Subroutine") then
                    goto [TNIDLTrueExit]  '* As this is a multi dec in the global scope
                end if
            case "is a local to Function"    '* Can clash with anything except another local to the same function, or globals
                If ((w2$ = "is a Local") OR (w2$ = "is a Global")) then
                    OverlappingDeclarations = True  '* As this is a multi dec in differing scopes
                    goto [TNIDLTrueExit]
                End If
                If    ((w2$ = "is a local to Function") AND (w3$ = SubName$)) then '* check sub name
                    goto [TNIDLTrueExit]  '* As this is a multi dec in the scope of the function SubName$
                End If
            case "is a local to Subroutine"
                If ((w2$ = "is a Local") OR (w2$ = "is a Global")) then
                    OverlappingDeclarations = True  '* As this is a multi dec in differing scopes
                    goto [TNIDLTrueExit]
                End If
                If ((w2$ = "is a local to Subroutine") AND (w3$ = SubName$)) then '* check sub name
                    goto [TNIDLTrueExit]   '* As this is a multi dec in the scope of the subroutine SubName$
                End If
            case "is a parameter of Function" '* Is allowed to clash with anything except globals and locals to this funsub
                If ((w2$ = "is a Local") OR (w2$ = "is a Global")) then
                    OverlappingDeclarations = True  '* As this is a multi dec in differing scopes
                    goto [TNIDLTrueExit]
                End If
                If ((w2$ = "is a local to Function") AND (w3$ = SubName$)) then
                    goto [TNIDLTrueExit]  '* As this is a multi dec in the scope of the function SubName$
                End If
            case "is a parameter of Subroutine"'* Is allowed to clash with anything except globals and locals to this funsub
                If ((w2$ = "is a Local") OR (w2$ = "is a Global")) then
                    OverlappingDeclarations = True  '* As this is a multi dec in differing scopes
                    goto [TNIDLTrueExit]
                End If
                If ((w2$ = "is a local to Subroutine") AND (w3$ = SubName$))  then
                    goto [TNIDLTrueExit]  '* As this is a multi dec in the scope of the subroutine SubName$
                End If
        End Select
    End If
next
goto [TNIDLExit]
[TNIDLTrueExit]
TokenInDecList = True
DecFoundAt = count
[TNIDLExit]
end function '* TokenInDecList

Function TokenInVarList()
TokenInVarList = False
'Loc count, w1$, w2$, w3$
for count = VarStartPointer + 1 to VarEndPointer - 1 step 1
    w1$ = trim$(word$(VarArray$(count), 1,","))  '*  <variable name>
    w2$ = trim$(word$(VarArray$(count), 2,","))  '* This is where the variable is found - e.g. "is in Function" . .
    w3$ = trim$(word$(VarArray$(count), 3,","))  '* This is the funsub name, or "Global"

    If Token$ = w1$ then    '* since the token's name is in the VarArray$, it may have the correct attributes . . .
        Select case  VarLoc$
            case "is Outside all FunSub"
                If (w2$ = "Global") goto [TIVLTrueExit]
            case "is in Function"
                If (w2$ = "is in Function") AND (w3$ = FunSubName$) goto [TIVLTrueExit]   '* check for matching function name
            case "is in Subroutine"
                If (w2$ = "is in Subroutine") AND (w3$ = FunSubName$) goto [TIVLTrueExit] '* check for matching subroutine name
        End Select
    End If
next
goto [TIVLExit]
[TIVLTrueExit]
TokenInVarList = True
CurrentVarArrayPtr = count
[TIVLExit]
end function '* TokenInVarList

SUB AddMdFlagToTokenInDecList
'* This Sub appends",Multi" etc., to the applicable Token's string
'Loc DAC$, string$
AddMdFlagToTokenInDecList = True
If OverlappingDeclarations = True then
    string$ = " but is declared in overlapping scopes"
else
    string$ =  " is declared multiple times"
end If
DAC$ = DecArray$(DecFoundAt)
If (((word$(DAC$, 7, ",") <> "but is declared in overlapping scopes") AND_
                    (word$(DAC$, 7, ",") <> "is declared multiple times"))) then
                    '* it's not yet identified as a  multiple declaration
    Call ReplaceWord string$, 7, DAC$
    DAC$ = DAC$ + ", " + str$(LineNum)
    DecArray$(DecFoundAt) = DAC$
Else
    DAC$ = DAC$ + ", " + str$(LineNum)
    DecArray$(DecFoundAt) = DAC$
End If
End SUB

SUB IncrementUseCountForTokenInVarList
'* This Sub Increments the "used" counter in the applicable Token's record.
'Loc Number, Number$, NewNumber$, Dummy$
Number$ = trim$(word$(VarArray$(CurrentVarArrayPtr), 5, ","))  '* number of times was used, as a string
Number = val(Number$)                      '* number of times was used, as a numeric
NewNumber$ = " " + trim$(str$(Number + 1)) '* number of times now used, as a string
Dummy$ = VarArray$(CurrentVarArrayPtr)
Call ReplaceWord NewNumber$, 5, Dummy$ '* Cos byref in ReplaceWord does not work for array references
VarArray$(CurrentVarArrayPtr) = Dummy$
End SUB   '* IncrementUseCountForTokenInVarList

SUB ReplaceWord NewString$, posn, ByRef InString$
'* Puts NewString$ in place of the posn'th word in Instring$ where words are comma delimited.
'* Note if a space is wanted in front of NewString$ it must be included in NewString$
'* The routine is not protected against "posn" being beyond the string length.
'Loc strBuild$, strRemain$, length, count, wordCount, oldStrLen,Dummy$
strBuild$ = ""
strRemain$ = InString$
wordCount = 0
length = len(InString$)
For count = 1 to len(InString$)    '* This strips off and stores the words prior to the one to be replaced
    If (left$(strRemain$, 1) <> ",") then
        strBuild$ = strBuild$ + left$(strRemain$, 1)
        length = length - 1
        strRemain$ = right$(InString$, length)
    Else
        strBuild$ = strBuild$ + ","
        strRemain$ = right$(InString$, length -1)  '* "trim" removed from new 1
        length = len(strRemain$)
        wordCount = wordCount +1
    End If
    If wordCount = posn - 1 then
        exit for
    End If
Next

'* Now need to remove the word to be replaced from strRemain$ - but it may be the last word in InString$
oldStrLen = Instr(strRemain$, ",")
If oldStrLen = 0 then '* we are replacing the last word
    InString$ = strBuild$ + NewString$
Else
    Dummy$ = trim$(right$(strRemain$, length - oldStrLen + 1))
    InString$ = strBuild$ + NewString$ + Dummy$
End If

End SUB '* ReplaceWord


SUB AddDeclarationStatus
'Loc String$, Dummy$
If VarDeclared() = False then
    String$ = " but NOT declared"
else
    String$ = " Declared"
end if
Dummy$ = VarArray$(CurrentVarArrayPtr)
Call ReplaceWord String$, 8, Dummy$   '* Cos byref in ReplaceWord does not work for array references
VarArray$(CurrentVarArrayPtr) = Dummy$
End SUB

Function VarDeclared()
VarDeclared = False
'Loc count, w1$, w2$, w3$, Dummy$
for count = DecStartPointer + 1 to DecEndPointer - 1 step 1
    w1$ = trim$(word$(DecArray$(count), 1,","))  '*  <variable name> in the DecArray
    w2$ = trim$(word$(DecArray$(count), 2,","))  '* This is the type of the item, e.g. Global, Function ...
    w3$ = trim$(word$(DecArray$(count), 3,","))  '* This is either a funsub name or "-"

    '* w1$ may contain a byref parameter. So the 'byref' must be removed before checking for a match.
    Call SubstituteC "", "byref", w1$
    w1$ = trim$(w1$)

    If Token$ = w1$ then    '* it may be in the Dec List since the token's name is in the DecArray$..
        '* First check to see if it is a declared Function, Subroutine, or Global or a 'global' 'Loc
        '* - in which case inside or outside a FunSub is irrelevant
        If ((w2$ = "is a Local") OR (w2$ = "is a Global")) OR_
            ((w2$ = "is a Subroutine") OR (w2$ = "is a Function")) goto [VDTrueExit]

        '* Now check for inside FunSub cases
        Select case  VarLoc$ 
            case "is in Function"
                If (_
                      (_
                         ((w2$ = "is a local to Function") OR (w2$ = "is a parameter of Function")) AND  (w3$ = FunSubName$)_
                      )_
                      OR (w2$ = "is a Function")_
                   ) goto [VDTrueExit]
            case "is in Subroutine"
                If (((w2$ = "is a local to Subroutine") OR_
                    (w2$ = "is a parameter of Subroutine")) AND_
                    (w3$ = FunSubName$))  goto [VDTrueExit]
        End Select
    End If
next
goto [VDExit]    '* as no matching declaration has been found
[VDTrueExit]
VarDeclared = True
Dummy$ = DecArray$(count)
Call ReplaceWord " is Used", 4, Dummy$   '* Cos byref in ReplaceWord does not work for array references
DecArray$(count) = Dummy$
[VDExit]

End Function '* VarDeclared




'******************************************************
'* END OF FUNCTIONS / SUBROUTINES WHICH HANDLE THE ARAYS
'******************************************************



'******************************************************
'* FUNCTIONS / SUBROUTINES WHICH TRANSFER ARAYS TO FILES
'******************************************************

SUB SaveGoodDecToFile
'Loc count, s, a$, t
print #Declarations, "Text analysed was found at " + SourcePath$
print #Declarations,"."
For count = DecStartPointer + 1 to DecEndPointer - 1
    a$ = DecArray$(count)
    s = instr(a$,"multiple")
    t = instr(a$,"in overlapping scopes")
    If (s = 0) AND (t = 0) then '* it's an OK declaration
        a$ = DecArray$(count)
        print #Declarations, a$
    end if
next
print #Declarations,"."
print #Declarations,"End of Good declarations file"
End SUB

SUB SaveBadDecToFile
'Loc count, a$, s, t
print #MultiDeclarations, "Text analysed was found at " + SourcePath$
print #MultiDeclarations,"."
For count = DecStartPointer + 1 to DecEndPointer - 1
    a$ = DecArray$(count)
    s = instr(a$,"multiple")
    t = instr(a$,"in overlapping scopes")
    If (s > 0) OR (t > 0) then '* it's not an OK declaration
        a$ = DecArray$(count)
        print #MultiDeclarations, a$
    end if
next
print #MultiDeclarations,"."
print #MultiDeclarations,"End of Multiple Declarations file"
End SUB

SUB SaveVariablesToFile
'Loc x$, count
print #Variables, "Text analysed was found at " + SourcePath$
print #Variables, "."
For count = VarStartPointer + 1 to VarEndPointer - 1
    x$ = VarArray$(count)
    print #Variables, x$
next
print #Variables, "."
print #Variables,"End of Variables file"
End SUB

SUB SaveUndeclaredVariablesToFile
'Loc count
print #UnDecVar, "Text analysed was found at " + SourcePath$
print #UnDecVar, "."
For count = VarStartPointer + 1 to VarEndPointer - 1
'Loc x$
    x$ = VarArray$(count)
    If instr((x$),"but NOT declared") <> 0 then '* it's an undeclared variable
        print #UnDecVar, x$
    end if
next
print #UnDecVar, "."
print #UnDecVar,"End of Undeclared Variables file"
End SUB

'Sub PrintArrays
''Loc count
'Print "--"
'For count = DecStartPointer+1 to DecEndPointer -1
'    print count, DecArray$(count)
'Next
'For count = VarStartPointer+1 to VarEndPointer -1
'    print count, VarArray$(count)
'Next
'End Sub '* Printarrays




'***********************************
'* Alternative way of getting the output path
'* - not used but works - slicker but misleading
'* savename$="test.txt"
'* filedialog "Select Folder to save", savename$, fullpath$
'* f$=afterlast$(fullpath$,"\")
'* p$=upto$(fullpath$,f$)
'* fullpath$=p$+savename$
'* print "Full path of the file chosen is ";fullpath$ 
'* print "Just the chosen folder path is "; p$ 
'*********************




























































































































































































































































































































































