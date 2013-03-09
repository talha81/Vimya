"""
" Coypright 2009 by Stefan Goebel <mail@ntworks.net> - <http://ntworks.net/>
"
" This program is free software: you can redistribute it and/or modify it under
" the terms of the GNU General Public License as published by the Free Software
" Foundation, either version 3 of the License, or (at your option) any later
" version.
"
" This program is distributed in the hope that it will be useful, but WITHOUT
" ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
" FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
" details.
"
" You should have received a copy of the GNU General Public License along with
" this program. If not, see <http://www.gnu.org/licenses/>.
"
" Vimya 0.1 - Execute buffer contents as MEL or Python scripts in Autodesk Maya
"
" Help is available in doc/vimya.txt or from within Vim with :help vimya. See
" the help file or the end of this file for license information.
"""

if exists ('g:loadedVimya') || &cp || ! has ('python')
    finish
endif
let g:loadedVimya = '0.2'

"""
" Configuration variables:
"""

if ! exists ('g:vimyaPort')
    let g:vimyaPort = 12345
endif

if ! exists ('g:vimyaHost')
    let g:vimyaHost = '127.0.0.1'
endif

if ! exists ('g:vimyaDefaultFiletype')
    let g:vimyaDefaultFiletype = 'python'
endif

if ! exists ('g:vimyaShowLog')
    let g:vimyaShowLog = 1
endif

"""
" Mappings:
"""

if ! hasmapto ('sendBufferToMaya')
    nnoremap <leader>sm :py sendBufferToMaya ()<cr>
    vnoremap <leader>sm :py sendBufferToMaya ()<cr>
    nnoremap <leader>sb :py sendBufferToMaya (True)<cr>
    vnoremap <leader>sb :py sendBufferToMaya (True)<cr>
endif

"""
" Main stuff (most of it is Python):
"""

let g:vimyaUseTail = 0
if exists ('g:Tail_Loaded')
    let vimyaUseTail = 1
endif

autocmd VimLeavePre * py __vimyaRemoveLog ()

python << EOP

import os
import socket
import tempfile
import vim
import time

logPath = ''
setLog = 0
tempFiles = []

# __vimyaRemoveLog ():
#
# If a logfile was written, delete it. Automatically executed when leaving Vim.
# Also, if some of the temporary file are left on disk, we delete them.

def __vimyaRemoveLog ():
    global logPath
    if logPath != '':
        __vimyaCloseLog ()
        try:
            os.unlink (logPath)
        except:
            pass
    for file in tempFiles:
        try:
            os.unlink (file)
        except:
            pass

# __vimyaCloseLog ():
#
# Issues a `cmdFileOutput -closeAll` command to close the log file.

def __vimyaCloseLog ():
    host = vim.eval ('g:vimyaHost')
    port = int (vim.eval ('g:vimyaPort'))
    try:
        connection = socket.socket (socket.AF_INET, socket.SOCK_STREAM)
        connection.settimeout (5)
        connection.connect ((host, port))
        connection.send ("cmdFileOutput -ca;\n")
        connection.close ()
    except:
        return __vimyaErrorMsg ('Could not close the log file.')
    return True

# errorMsg (message = <string>):
#
# Print the error message given by <string> with the appropriate highlighting.
# Returns always False.

def __vimyaErrorMsg (message):
    vim.command ('echohl ErrorMsg')
    vim.command ("echo \"%s\"" % message )
    vim.command ('echohl None')
    return False

# sendBufferToMaya (forceBuffer = False):
#
# Saves the buffer (or a part of it) to a temporary file and instructs Maya to
# source this file. In visual mode only the selected lines are used, else the
# complete buffer. In visual mode, forceBuffer may be set to True to force
# executing the complete buffer. If selection starts (or ends) in the middle of
# a line, the complete line is included! Returns False if an error occured,
# else True.


def sendBufferToMaya (forceBuffer = False):

    global logPath, setLog, tempFiles

    type        = vim.eval ('&ft')
    print "fileType detected is", type
    defaultType = vim.eval ('g:vimyaDefaultFiletype')
    host        = vim.eval ('g:vimyaHost')
    port        = int (vim.eval ('g:vimyaPort'))
    tail        = int (vim.eval ('g:vimyaUseTail'))
    showLog     = int (vim.eval ('g:vimyaShowLog'))

    if type != '' and type != 'python' and type != 'mel':
        return __vimyaErrorMsg (
                "Error: Supported filetypes: 'python', 'mel', None."
            )

    if logPath == '' and tail == 1 and showLog == 1:
        (logHandle, logPath) = tempfile.mkstemp (
                suffix = '.log', prefix = 'vimya.', text = 1
            )
        setLog = 1

    (tmpHandle, tmpPath) = tempfile.mkstemp (
            suffix = '.py', prefix = 'vimya.', text = 1
        )
    tempFiles.append (tmpPath)

    vStart = vim.current.buffer.mark ('<')
    if (vStart is None) or (forceBuffer):
        for line in vim.current.buffer:
            os.write (tmpHandle, "%s\n" % line)
    else:
        vEnd = vim.current.buffer.mark ('>')
        for line in vim.current.buffer [vStart [0] - 1 : vEnd [0]]:
            os.write (tmpHandle, "%s\n" % line)
    os.close (tmpHandle)

    try:
        connection = socket.socket (socket.AF_INET, socket.SOCK_STREAM)
        connection.settimeout (5)
    except:
        return __vimyaErrorMsg ('Could not create socket.')
    try:
        connection.connect ((host, port))
    except:
        return __vimyaErrorMsg ('Could not connect to the command port.')

    try:

        if setLog == 1:
            connection.send (
                    "cmdFileOutput -o \"%s\";\n" % logPath.replace ('\\', '/')
                )
            k = int(vim.eval('&splitbelow'))
            vim.command ("set splitbelow")
            vim.command ("STail %s" % logPath)
            if k == 1:
                vim.command ("set splitbelow")
            else:
                vim.command ("set nosplitbelow")
            setLog = 0

        connection.send ("commandEcho -state on -lineNumbers on;\n")
        if type == 'python' or (type == '' and defaultType == 'python'):
            connection.send (
                    "python (\"execfile ('%s')\");\n" % \
                        tmpPath.replace ('\\', '/')
                )
        elif (type == 'mel' or (type == '' and defaultType == 'mel')):
            print "mel command"
            connection.send ("source \"%s\";\n" % tmpPath.replace ('\\', '/'))

        connection.send ("commandEcho -state off -lineNumbers off;\n")
        connection.send (
                "sysFile -delete \"%s\";\n" % tmpPath.replace ('\\', '/')
            )

        if showLog and tail:
            time.sleep(2)
            vim.command('call tail#Refresh()')


    except:
        return __vimyaErrorMsg ('Could not send the commands to Maya.')

    try:
        connection.close ()
    except:
        return __vimyaErrorMsg ('Could not close socket.')

    return True

def resetVimyaTail():
    tail = int (vim.eval ('g:vimyaUseTail'))
    if tail:
        k = int(vim.eval('&splitbelow'))
        vim.command ("set splitbelow")
        vim.command ("STail %s" % logPath)
        if k == 1:
            vim.command ("set splitbelow")
        else:
            vim.command ("set nosplitbelow")
        return True
    return False

def resetVimyaLog():
    tail = int (vim.eval ('g:vimyaUseTail'))
    if tail:
        __vimyaCloseLog()
        __vimyaRemoveLog()
        vim.command('pclose')
        global logPath
        logPath=''
        sendBufferToMaya()
        return True
    return False

EOP

" vim: set et si nofoldenable ft=python sts=4 sw=4 tw=79 ts=4 fenc=utf8 :
