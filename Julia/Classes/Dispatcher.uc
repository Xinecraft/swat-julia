class Dispatcher extends Engine.Actor
 implements InterestedInCommandDispatched,
            InterestedInEventBroadcast,
            InterestedInPlayerDisconnected;

/**
 * Copyright (c) 2014 Sergei Khoroshilov <kh.sergei@gmail.com>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

/**
 * Length of autogenerated random key assigned to a dispatched command
 * @type int
 */
var config int CommandIdLength;

/**
 * Time in seconds a player is allowed to issue another commandW
 * @type float
 */
var config float CommandThreshold;

/**
 * Time in seconds a command should be failed if not responded within the time
 * @type float
 */
var config float CommandTimeout;


struct sBoundCommand
{
    /**
     * Command name
     * @type string
     */
    var string Name;

    /**
     * Reference to the receiver all commands with this name should be dispatched to
     * @type interface'InterestedInCommandDispatched'
     */
    var InterestedInCommandDispatched Receiver;

    /**
     * Command description (displayed in the !command help text)
     * @type string
     */
    var string Description;

    /**
     * Command usage desription (displayed in the !command help text and )
     * @type string
     */
    var string Usage;

    /**
     * Indicate whether the command arguments contain sensitive data
     * that should not be displayed back to the user
     * @type bool
     */
    var bool bSensitive;
};

struct sDispatchedCommand
{
    /**
     * Index of the corresponding bound command
     * @type int
     */
    var int BoundIndex;

    /**
     * Dispatched command unique id
     * @type string
     */
    var string Id;

    /**
     * Time the command was dispatched at (Level.TimeSeconds)
     * @type float
     */
    var float TimeDispatched;

    /**
     * The player that has issued the command
     * @type class'Player'
     */
    var Player Player;

    /**
     * Indicate whether the command receiver has replied 
     * @type bool
     */
    var bool bReplied;
};

/**
 * Reference to the Julia's Core instance
 * @type class'Core'
 */
var protected Core Core;

/**
 * List of bound commands
 * @type array<struct'sBoundCommand'>
 */
var protected array<sBoundCommand> BoundCommands;

/**
 * List of dispatched commands
 * @type array<struct'sDispatchedCommand'>
 */
var protected array<sDispatchedCommand> DispatchedCommands;

/**
 * Disable the Tick event
 * 
 * @return  void
 */
public function PreBeginPlay()
{
    Super.PreBeginPlay();
    self.Disable('Tick');
}

/**
 * Clean up irrelevant dispatched commands
 */
event Timer()
{
    self.HandleDispatchedCommands();
}

/**
 * Initialize the instance
 * 
 * @param   class'Core' Core
 *          Reference to the Core instance
 * @return  void
 */
public function Init(Core Core)
{
    self.Core = Core;

    self.Core.RegisterInterestedInPlayerDisconnected(self);
    self.Core.RegisterInterestedInEventBroadcast(self);
    // Register the help command
    self.Bind(
        "help", 
        self, 
        self.Core.GetLocale().Translate("DispatcherHelpUsage"),
        self.Core.GetLocale().Translate("DispatcherHelpDescription")
    );
    // Use fixed tick rate
    self.SetTimer(class'Core'.const.DELTA, true);
}

/**
 * Attempt to parse a command from either Say or TeamSay event message
 * 
 * @see InterestedInEventBroadcast.OnEventBroadcast
 */
public function bool OnEventBroadcast(Player Caller, Actor Sender, name Type, string Msg, optional PlayerController Receiver, optional bool bHidden)
{
    local string Name, Message;
    local array<string> Words;

    switch (Type)
    {
        case 'Say' :
        case 'TeamSay' :
            break;
        default :
            return true;
    }

    Message = class'Utils.StringUtils'.static.Filter(Msg);

    if (Mid(Message, 0, 1) == "!" && Mid(Message, 1, 1) != "!")  // Ignore !!+
    {
        if (Caller != None)
        {
            Words = class'Utils.StringUtils'.static.SplitWords(Mid(Message, 1));

            if (Words.Length > 0)
            {
                // The word is translated into a command name
                Name = Words[0];
                // The rest become the command arguments
                Words.Remove(0, 1);
                // Get the caller
                self.Dispatch(Name, Words, Caller);
                // Hide this event from chat
                return false;
            }
        }
    }
    return true;
}

/**
 * Respond to user whenever the help command is issued
 * 
 * @see InterestedInCommandDispatched.OnCommandDispatched
 */
public function OnCommandDispatched(Dispatcher Dispatcher, string Name, string Id, array<string> Args, Player Player)
{
    local string Response;

    switch (Name)
    {
        case "help":
            Response = self.Core.GetLocale().Translate(
                "DispatcherCommandList",
                class'Utils.ArrayUtils'.static.Join(self.GetBoundCommandNames(), ", ")
            );
            break;
        default:
            return;
    }

    self.Respond(Id, Response);
}

/**
 * Remove dispatched commands issued by the disconnected player
 * 
 * @see InterestedInPlayerDisconnected.OnPlayerDisconnected
 */
public function OnPlayerDisconnected(Player Player)
{
    local int i;

    for (i = self.DispatchedCommands.Length-1; i >= 0 ; i--)
    {
        if (self.DispatchedCommands[i].Player == Player)
        {
            self.DispatchedCommands[i].Player = None;
            self.DispatchedCommands.Remove(i, 1);
        }
    }
}

/**
 * Attempt to bind a command
 * 
 * @param   string Name
 *          Case-insensitive command name
 * @param   interface'InterestedInCommandDispatched' Receiver
 *          A InterestedInCommandDispatched instance the command shoukd be bound with
 * @param   string Usage
 * @param   string Description
 *          Command description
 * @param   bool bSensitive (optional)
 *          Indicate whether command arguments should not be displayed back to user
 * @return  void
 */
public function Bind(string Name, InterestedInCommandDispatched Receiver, string Usage, string Description, optional bool bSensitive)
{
    local sBoundCommand Command;

    Name = Lower(class'Utils.StringUtils'.static.Strip(class'Utils.StringUtils'.static.DropSpace(Name)));

    // Dont allow whitespace in a command name
    if (Name == "")
    {
        log(self $ ": wont register an empty command");
        return;
    }

    // Dont allow duplicate command entries
    if (class'Utils.ArrayUtils'.static.Search(self.GetBoundCommandNames(), Name) >= 0)
    {
        log(self $ ": " $ Name $ " has already been bound");
        return;
    }

    Command.Name = Name;
    Command.Description = Description;
    Command.Usage = Usage;
    Command.bSensitive = bSensitive;
    Command.Receiver = Receiver;

    self.BoundCommands[self.BoundCommands.Length] = Command;

    log(self $ ": successfully registered " $ Name $ " (" $ Receiver $ ")");
}

/**
 * Attemp to unbind a command
 * 
 * @param   string Name
 * @param   interface'InterestedInCommandDispatched' Receiver
 * @return  void
 */
public function Unbind(string Name, InterestedInCommandDispatched Receiver)
{
    local int i;

    for (i = self.BoundCommands.Length-1; i >= 0; i--)
    {
        if (self.BoundCommands[i].Name ~= Name && self.BoundCommands[i].Receiver == Receiver)
        {
            log(self $ ": unregistering " $ self.BoundCommands[i].Name $ " (" $ Receiver $ ")");
            self.BoundCommands[i].Receiver = None;
            self.BoundCommands.Remove(i, 1);
            return;
        }
    }
}

/**
 * Unbind all commands that have been bound with specific Receiver
 * 
 * @param   interface'InterestedInCommandDispatched' Receiver
 * @return  void
 */
public function UnbindAll(InterestedInCommandDispatched Receiver)
{
    local int i;

    for (i = self.BoundCommands.Length-1; i >= 0; i--)
    {
        if (self.BoundCommands[i].Receiver == Receiver)
        {
            log(self $ ": unregistering " $ self.BoundCommands[i].Name $ " (" $ Receiver $ ")");
            self.BoundCommands[i].Receiver = None;
            self.BoundCommands.Remove(i, 1);
        }
    }
}

/**
 * Throw a custom error message 
 * 
 * @param   string Id
 *          Dispatched command unique id
 * @param   string Error
 *          Error message
 * @return  void
 */
public function ThrowError(string Id, string Error)
{
    local int i;
    local sBoundCommand Command;

    i = self.GetDispatchedCommandById(Id);

    if (i == -1)
    {
        return;
    }

    Command = self.BoundCommands[self.DispatchedCommands[i].BoundIndex];

    self.PrintText(class'Utils.StringUtils'.static.Format(Error, Command.Name), self.DispatchedCommands[i].Player);

    self.DispatchedCommands[i].bReplied = true;
}

/**
 * Throw an invalid usage error
 * 
 * @param   string Id
 * @return  void
 */
public function ThrowUsageError(string Id)
{
    self.ThrowError(Id, self.Core.GetLocale().Translate("DispatcherUsageError"));
}

/**
 * Throw a permission error message
 * 
 * @param   string Id
 * @return  void
 */
public function ThrowPermissionError(string Id)
{
    self.ThrowError(Id, self.Core.GetLocale().Translate("DispatcherPermissionError"));
}

/**
 * Display command successful response
 *
 * @param   string Id
 *          Command response id
 * @param   string Message
 *          Command result
 * @return  void
 */
public function Respond(string Id, string Response)
{
    local int i;

    i = self.GetDispatchedCommandById(Id);

    if (i == -1 || self.DispatchedCommands[i].bReplied)
    {
        return;
    }

    self.PrintText(Response, self.DispatchedCommands[i].Player);
    self.DispatchedCommands[i].bReplied = true;
}

/**
 * Attempt to dispatch a player command
 * 
 * @param   string CommandName
 * @param   array<string> Args
 * @param   class'Player' Player
 * @return  void
 */
protected function Dispatch(string CommandName, array<string> Args, Player Player)
{
    local int i;

    if (Player == None)
    {
        return;
    }

    if (!self.IsAllowedToIssueCommands(Player))
    {
        self.PrintText(self.Core.GetLocale().Translate("DispatcherCommandCooldown"), Player);
        return;
    }

    i = self.GetBoundCommandByName(CommandName);

    if (i == -1)
    {
        self.PrintText(self.Core.GetLocale().Translate("DispatcherCommandInvalid", CommandName), Player);
        return;
    }

    // Command header
    self.PrintHeader(CommandName, Args, self.BoundCommands[i].bSensitive, Player);
    // Display help menu instead
    if (Args.Length > 0 && Args[0] ~= "help")
    {
        self.PrintHelp(self.BoundCommands[i].Name, self.BoundCommands[i].Usage, self.BoundCommands[i].Description, Player);
    }
    else
    {
        log(self $ ": dispatching " $ CommandName $ " from " $ Player.GetName() $ " to " $ self.BoundCommands[i].Receiver);

        self.BoundCommands[i].Receiver.OnCommandDispatched(
            self,
            Lower(CommandName), 
            self.QueueDispatchedCommand(i, Player),
            Args, 
            Player
        );
    }
}

/**
 * Return an array of bound command names
 * 
 * @return  array<string>
 */
protected function array<string> GetBoundCommandNames()
{
    local int i;
    local array<string> Names;

    for (i = 0; i < self.BoundCommands.Length; i++)
    {
        Names[Names.Length] = self.BoundCommands[i].Name;
    }

    return Names;
}

/**
 * Return index of the bound command matching the given name
 * 
 * @param   string Name
 * @return  int
 */
protected function int GetBoundCommandByName(string Name)
{
    local int i;

    for (i = 0; i < self.BoundCommands.Length; i++)
    {
        if (self.BoundCommands[i].Name ~= Name)
        {
            return i;
        }
    }

    return -1;
}

/**
 * Return index of the dispatched command matching the given key
 * 
 * @param   string Id
 * @return  int
 */
protected function int GetDispatchedCommandById(string Id)
{
    local int i;

    for (i = 0; i < self.DispatchedCommands.Length; i++)
    {
        if (self.DispatchedCommands[i].Id == Id)
        {
            return i;
        }
    }

    return -1;
}

/**
 * Attempt to remove timed out commands and display appropriate output
 * 
 * @return  void
 */
protected function HandleDispatchedCommands()
{
    local int i;

    for (i = self.DispatchedCommands.Length-1; i >= 0; i--)
    {
        if (!self.DispatchedCommands[i].bReplied)
        {
            // Command has timed out
            if (self.DispatchedCommands[i].TimeDispatched + self.CommandTimeout < Level.TimeSeconds)
            {
                self.PrintText(self.Core.GetLocale().Translate("DispatcherCommandTimedout"), self.DispatchedCommands[i].Player);
                self.DispatchedCommands[i].bReplied = true;
            }
        }
        else if (self.DispatchedCommands[i].TimeDispatched + self.CommandThreshold < Level.TimeSeconds)
        {
            self.DispatchedCommands.Remove(i, 1);
        }
    }
}

/**
 * Tell whether the given player is allowed to issue commands
 * 
 * @param   class'Player' Player
 * @return  bool
 */
protected function bool IsAllowedToIssueCommands(Player Player)
{
    local int i;

    for (i = self.DispatchedCommands.Length-1; i >= 0 ; i--)
    {
        if (self.DispatchedCommands[i].Player == Player)
        {
            return false;
        }
    }
    return true;
}

/**
 * Queue a new dispatched command. Return the command unique id.
 * 
 * @param   int BoundIndex
 *          BoundCommands array index of the bound command
 * @param   class'Player' Player
 *          The caller
 * @return  string
 */
protected function string QueueDispatchedCommand(int BoundIndex, Player Player)
{
    local sDispatchedCommand Dispatched;

    // Generate a random id
    Dispatched.Id = class'Utils.StringUtils'.static.Random(self.CommandIdLength, ":alpha:");
    
    Dispatched.BoundIndex = BoundIndex;
    Dispatched.Player = Player;
    Dispatched.TimeDispatched = Level.TimeSeconds;

    self.DispatchedCommands[self.DispatchedCommands.Length] = Dispatched;

    return Dispatched.Id;
}

/**
 * Format command output
 * 
 * @param   string Text
 *          Unformatted text
 * @param   class'Player' Player
 *          Receiver
 * @return  void
 */
protected function PrintText(string Text, Player Player)
{
    local int i;
    local array<string> Lines;

    // Split text in lines
    Lines = class'Utils.StringUtils'.static.Part(class'Utils.StringUtils'.static.NormNewline(Text), "\n");

    for (i = 0; i < Lines.Length; i++)
    {
        class'Utils.LevelUtils'.static.TellPlayer(
            self.Level, 
            self.Core.GetLocale().Translate("DispatcherOutputLine", Lines[i]),
            Player.GetPC(), 
            self.Core.GetLocale().Translate("DispatcherOutputColor")
        );
    }
}

/**
 * Print command help
 * 
 * @param   string Name
 * @param   string Usage
 * @param   string Description
 * @param   class;Player' Player
 * @return  void
 */
protected function PrintHelp(string Name, string Usage, string Description, Player Player)
{
    self.PrintText(
        self.Core.GetLocale().Translate(
            "DispatcherCommandHelp",
            Description,
            class'Utils.StringUtils'.static.Format(Usage, Name)
        ),
        Player
    );
}

/**
 * Print command header
 * 
 * @param   string Name
 * @param   array<string> Args
 * @param   bool bSensitive
 * @param   class'Player' Player
 * @return  void
 */
protected function PrintHeader(string Name, array<string> Args, bool bSensitive, Player Player)
{
    // Hide arguments from output
    if (Args.Length > 0 && bSensitive)
    {
        Args.Remove(0, Args.Length);
    }
    self.PrintText(
        class'Utils.StringUtils'.static.RStrip(
            self.Core.GetLocale().Translate("DispatcherOutputHeader", Name, class'Utils.ArrayUtils'.static.Join(Args, " ") $ " ")
        ),
        Player
    );
}

event Destroyed()
{
    self.Core.UnregisterInterestedInEventBroadcast(self);
    self.Core.UnregisterInterestedInPlayerDisconnected(self);

    while (self.DispatchedCommands.Length > 0)
    {
        self.DispatchedCommands[0].Player = None;
        self.DispatchedCommands.Remove(0, 1);
    }

    while (self.BoundCommands.Length > 0)
    {
        self.BoundCommands[0].Receiver = None;
        self.BoundCommands.Remove(0, 1);
    }

    self.Core = None;

    Super.Destroyed();
}

defaultproperties
{
    CommandIdLength=8;
    CommandThreshold=3.0;
    CommandTimeout=2.0;
}

/* vim: set ft=java: */
