using System;

namespace CcShot.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            try
            {
                var message = (args.ExceptionObject as Exception)?.Message ?? "未知错误";
                System.Windows.MessageBox.Show("ccShot 遇到错误：" + message, "ccShot", System.Windows.MessageBoxButton.OK,
                    System.Windows.MessageBoxImage.Error);
            }
            catch (Exception)
            {
                // Nothing sensible left to do; the process is going down anyway.
            }
        };

        var app = new App();
        app.Run();
    }
}
